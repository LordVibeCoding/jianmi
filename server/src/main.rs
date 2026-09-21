//! 简密同步服务端 —— 零知识：只存密文 blob，无法解密任何内容。
//!
//! 用法:
//!   jianmi-server [--addr 0.0.0.0:8787] [--data ./data]
//!
//! 首次启动自动生成访问令牌，写入 <data>/token.txt 并打印到控制台。
//! API 鉴权: Authorization: Bearer <token>

use axum::{
    body::Bytes,
    extract::State,
    http::{header, HeaderMap, StatusCode},
    middleware::{self, Next},
    response::{Html, IntoResponse, Response},
    routing::{get, post, put},
    Json, Router,
};
use rand::RngCore;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs,
    net::SocketAddr,
    path::PathBuf,
    sync::{Arc, Mutex},
};

// ── 状态 ─────────────────────────────────────────────────
#[derive(Clone)]
struct AppState {
    db: Arc<Mutex<Connection>>,
    token_hash: [u8; 32],
    data_dir: PathBuf,
}

// ── 协议模型（与 SyncEngine.swift 对齐）───────────────────
#[derive(Serialize, Deserialize)]
struct SyncRecord {
    uuid: String,
    version: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    seq: Option<i64>,
    deleted: bool,
    payload: String,
}

#[derive(Deserialize)]
struct PullRequest {
    since_seq: i64,
}

#[derive(Serialize)]
struct PullResponse {
    latest_seq: i64,
    entries: Vec<SyncRecord>,
}

#[derive(Deserialize)]
struct PushRequest {
    entries: Vec<SyncRecord>,
}

#[derive(Serialize)]
struct AcceptedRecord {
    uuid: String,
    seq: i64,
}

#[derive(Serialize)]
struct PushResponse {
    accepted: Vec<AcceptedRecord>,
    conflicts: Vec<SyncRecord>,
}

// ── 入口 ─────────────────────────────────────────────────
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut addr = "0.0.0.0:8787".to_string();
    let mut data_dir = PathBuf::from("./data");

    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--addr" => {
                addr = args.get(i + 1).cloned().unwrap_or(addr);
                i += 2;
            }
            "--data" => {
                data_dir = PathBuf::from(args.get(i + 1).cloned().unwrap_or_default());
                i += 2;
            }
            _ => i += 1,
        }
    }

    fs::create_dir_all(&data_dir)?;

    // 令牌：首次生成 64 字符随机串
    let token_path = data_dir.join("token.txt");
    let token = if token_path.exists() {
        fs::read_to_string(&token_path)?.trim().to_string()
    } else {
        let mut bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes);
        let t = hex::encode(bytes);
        fs::write(&token_path, &t)?;
        println!("════════════════════════════════════════════════════════");
        println!("  首次启动，已生成访问令牌（请填入简密 App 的同步设置）：");
        println!("  {t}");
        println!("  令牌保存在: {}", token_path.display());
        println!("════════════════════════════════════════════════════════");
        t
    };
    let token_hash: [u8; 32] = Sha256::digest(token.as_bytes()).into();

    // 数据库
    let db = Connection::open(data_dir.join("jianmi-server.sqlite"))?;
    db.execute_batch(
        "PRAGMA journal_mode=WAL;
         CREATE TABLE IF NOT EXISTS entries(
             uuid TEXT PRIMARY KEY,
             version INTEGER NOT NULL,
             seq INTEGER NOT NULL,
             deleted INTEGER NOT NULL DEFAULT 0,
             payload TEXT NOT NULL,
             updated_at TEXT NOT NULL DEFAULT (datetime('now'))
         );
         CREATE INDEX IF NOT EXISTS idx_entries_seq ON entries(seq);
         CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);",
    )?;

    let state = AppState {
        db: Arc::new(Mutex::new(db)),
        token_hash,
        data_dir,
    };

    // API 路由（需鉴权）
    let api = Router::new()
        .route("/api/health", get(health))
        .route("/api/sync/pull", post(pull))
        .route("/api/sync/push", post(push))
        .route("/api/vault/meta", put(put_meta).get(get_meta))
        .layer(middleware::from_fn_with_state(state.clone(), auth));

    // Web 页（无需鉴权即可加载页面，数据仍需令牌）
    let app = Router::new()
        .route("/", get(index_html))
        .route("/sodium.js", get(sodium_js))
        .merge(api)
        .with_state(state);

    let socket: SocketAddr = addr.parse()?;
    println!("简密服务端已启动: http://{socket}");
    let listener = tokio::net::TcpListener::bind(socket).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(async {
            tokio::signal::ctrl_c().await.ok();
        })
        .await?;
    Ok(())
}

// ── 鉴权中间件 ────────────────────────────────────────────
async fn auth(
    State(state): State<AppState>,
    headers: HeaderMap,
    request: axum::extract::Request,
    next: Next,
) -> Response {
    let ok = headers
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .map(|t| {
            let h: [u8; 32] = Sha256::digest(t.trim().as_bytes()).into();
            // 常数时间比较
            h.iter()
                .zip(state.token_hash.iter())
                .fold(0u8, |acc, (a, b)| acc | (a ^ b))
                == 0
        })
        .unwrap_or(false);

    if !ok {
        return (StatusCode::UNAUTHORIZED, "invalid token").into_response();
    }
    next.run(request).await
}

// ── 处理器 ───────────────────────────────────────────────
async fn health() -> &'static str {
    "ok"
}

async fn pull(
    State(state): State<AppState>,
    Json(req): Json<PullRequest>,
) -> Result<Json<PullResponse>, AppError> {
    let db = state.db.lock().unwrap();
    let latest_seq: i64 = db
        .query_row(
            "SELECT COALESCE(value, '0') FROM meta WHERE key='seq'",
            [],
            |r| r.get::<_, String>(0),
        )
        .unwrap_or_else(|_| "0".into())
        .parse()
        .unwrap_or(0);

    let mut stmt = db.prepare(
        "SELECT uuid, version, seq, deleted, payload FROM entries
         WHERE seq > ?1 ORDER BY seq ASC",
    )?;
    let entries = stmt
        .query_map([req.since_seq], |row| {
            Ok(SyncRecord {
                uuid: row.get(0)?,
                version: row.get(1)?,
                seq: Some(row.get(2)?),
                deleted: row.get::<_, i64>(3)? != 0,
                payload: row.get(4)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(Json(PullResponse {
        latest_seq,
        entries,
    }))
}

async fn push(
    State(state): State<AppState>,
    Json(req): Json<PushRequest>,
) -> Result<Json<PushResponse>, AppError> {
    let mut db = state.db.lock().unwrap();
    let tx = db.transaction()?;

    let mut seq: i64 = tx
        .query_row(
            "SELECT COALESCE(value, '0') FROM meta WHERE key='seq'",
            [],
            |r| r.get::<_, String>(0),
        )
        .unwrap_or_else(|_| "0".into())
        .parse()
        .unwrap_or(0);

    let mut accepted = Vec::new();
    let mut conflicts = Vec::new();

    for record in req.entries {
        let server_version: Option<i64> = tx
            .query_row(
                "SELECT version FROM entries WHERE uuid=?1",
                [&record.uuid],
                |r| r.get(0),
            )
            .ok();

        match server_version {
            // 版本单调递增才接受；否则返回服务器版本让客户端合并
            Some(sv) if record.version <= sv => {
                let existing = tx.query_row(
                    "SELECT uuid, version, seq, deleted, payload FROM entries WHERE uuid=?1",
                    [&record.uuid],
                    |row| {
                        Ok(SyncRecord {
                            uuid: row.get(0)?,
                            version: row.get(1)?,
                            seq: Some(row.get(2)?),
                            deleted: row.get::<_, i64>(3)? != 0,
                            payload: row.get(4)?,
                        })
                    },
                )?;
                conflicts.push(existing);
            }
            _ => {
                seq += 1;
                tx.execute(
                    "INSERT INTO entries(uuid, version, seq, deleted, payload, updated_at)
                     VALUES(?1, ?2, ?3, ?4, ?5, datetime('now'))
                     ON CONFLICT(uuid) DO UPDATE SET
                        version=excluded.version, seq=excluded.seq,
                        deleted=excluded.deleted, payload=excluded.payload,
                        updated_at=excluded.updated_at",
                    rusqlite::params![
                        record.uuid,
                        record.version,
                        seq,
                        record.deleted as i64,
                        record.payload
                    ],
                )?;
                accepted.push(AcceptedRecord {
                    uuid: record.uuid,
                    seq,
                });
            }
        }
    }

    tx.execute(
        "INSERT INTO meta(key, value) VALUES('seq', ?1)
         ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [seq.to_string()],
    )?;
    tx.commit()?;

    Ok(Json(PushResponse {
        accepted,
        conflicts,
    }))
}

async fn put_meta(State(state): State<AppState>, body: Bytes) -> Result<StatusCode, AppError> {
    fs::write(state.data_dir.join("vault-meta.json"), &body)
        .map_err(|e| AppError(anyhow::anyhow!(e)))?;
    Ok(StatusCode::NO_CONTENT)
}

async fn get_meta(State(state): State<AppState>) -> Response {
    match fs::read(state.data_dir.join("vault-meta.json")) {
        Ok(data) => ([(header::CONTENT_TYPE, "application/json")], data).into_response(),
        Err(_) => (StatusCode::NOT_FOUND, "meta not uploaded").into_response(),
    }
}

// ── 内嵌 Web 页 ──────────────────────────────────────────
async fn index_html() -> Html<&'static str> {
    Html(include_str!("../../web/index.html"))
}

async fn sodium_js() -> Response {
    (
        [(header::CONTENT_TYPE, "application/javascript")],
        include_str!("../../web/sodium.js"),
    )
        .into_response()
}

// ── 错误处理 ─────────────────────────────────────────────
struct AppError(anyhow::Error);

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        (StatusCode::INTERNAL_SERVER_ERROR, self.0.to_string()).into_response()
    }
}

impl<E: Into<anyhow::Error>> From<E> for AppError {
    fn from(err: E) -> Self {
        Self(err.into())
    }
}
