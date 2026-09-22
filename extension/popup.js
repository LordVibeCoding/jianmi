// 简密扩展 · Popup
const BASE = "http://127.0.0.1:48787";
const TYPE_ICON = {
  login: ["🔑", "#2f81f7"],
  website: ["🌐", "#2f81f7"], app: ["📱", "#6e7dfa"], bank_card: ["💳", "#3fb950"],
  wallet: ["🪙", "#d29922"], ssh: ["🖥", "#a371f7"], identity: ["🪪", "#39c5cf"],
  note: ["📝", "#e3b341"],
};

const $dot = document.getElementById("dot");
const $content = document.getElementById("content");
let token = "";
let currentTab = null;

const esc = (s) => String(s ?? "").replace(/[&<>"']/g,
  c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

async function api(path, options = {}) {
  const res = await fetch(BASE + path, {
    ...options,
    headers: {
      "Authorization": "Bearer " + token,
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
  });
  if (res.status === 401) throw new Error("unauthorized");
  if (res.status === 423) throw new Error("locked");
  if (!res.ok) throw new Error("http " + res.status);
  return res.status === 204 ? null : res.json();
}

function toast(text) {
  const t = document.createElement("div");
  t.className = "toast";
  t.textContent = text;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 1400);
}

// ── 状态视图 ─────────────────────────────────────────────
function pairingView(message = "") {
  $dot.className = "dot off";
  $content.innerHTML = `
    <div class="state">
      <div class="big">🔗</div>
      首次使用需要配对<br>
      <span style="font-size:11px">打开简密 App → 设置 → 浏览器扩展，复制配对令牌</span>
      ${message ? `<div style="color:var(--red);font-size:11px;margin-top:6px">${esc(message)}</div>` : ""}
      <div style="margin-top:12px">
        <input id="tokenInput" type="password" placeholder="粘贴配对令牌"
          style="width:100%;padding:8px;border-radius:8px;background:var(--panel);border:1px solid var(--border);color:var(--text);outline:none">
        <button id="pairBtn" style="width:100%;margin-top:8px;padding:8px;border-radius:8px;border:none;background:var(--accent);color:#fff;font-weight:600;cursor:pointer">配对</button>
      </div>
    </div>`;
  document.getElementById("pairBtn").onclick = async () => {
    token = document.getElementById("tokenInput").value.trim();
    if (!token) return;
    try {
      await api("/api/bridge/status");
      await chrome.storage.local.set({ token });
      init();
    } catch (e) {
      pairingView(e.message === "unauthorized" ? "令牌无效" : "无法连接简密 App，请确认 App 正在运行");
    }
  };
}

function offlineView() {
  $dot.className = "dot off";
  $content.innerHTML = `
    <div class="state">
      <div class="big">💤</div>
      未检测到简密 App<br>
      <span style="font-size:11px">请先启动 Mac 上的简密</span>
    </div>`;
}

function lockedView() {
  $dot.className = "dot locked";
  $content.innerHTML = `
    <div class="state">
      <div class="big">🔒</div>
      简密已锁定<br>
      <span style="font-size:11px">请在 Mac 上解锁（⌥⌘P 或点菜单栏图标）</span>
    </div>`;
}

// ── 主视图 ───────────────────────────────────────────────
let catFilter = "";   // "" = 当前站点, 其他 = 分类 id

async function mainView() {
  $dot.className = "dot on";
  const host = currentTab?.url ? new URL(currentTab.url).hostname : "";

  $content.innerHTML = `
    <div id="topRow">
      <input id="search" placeholder="搜索简密…" autocomplete="off">
      <select id="catSel"><option value="">当前站点</option></select>
    </div>
    <div id="list"></div>
    <footer>
      <button class="savebtn" id="toggleSave">＋ 保存当前页面的新账号</button>
      <div id="saveForm">
        <input id="sTitle" placeholder="名称">
        <input id="sUser" placeholder="账号">
        <div class="pwrow">
          <input id="sPwd" placeholder="密码" autocomplete="off">
          <button id="sGen" title="生成强密码">🎲</button>
        </div>
        <div class="saverow">
          <button id="sCancel">取消</button>
          <button class="go" id="sGo">保存到简密</button>
        </div>
      </div>
    </footer>`;

  const $list = document.getElementById("list");
  const $search = document.getElementById("search");
  const $catSel = document.getElementById("catSel");

  // 分类下拉（含自定义分类，动态拉取）
  try {
    const { categories } = await api("/api/bridge/categories");
    for (const c of (categories || [])) {
      const opt = document.createElement("option");
      opt.value = c.id;
      opt.textContent = c.name;
      $catSel.appendChild(opt);
    }
    $catSel.value = catFilter;
    $catSel.onchange = () => {
      catFilter = $catSel.value;
      load($search.value.trim());
    };
  } catch (_) {}

  async function load(query) {
    const params = new URLSearchParams();
    if (query) params.set("q", query);
    if (catFilter) {
      params.set("category", catFilter);
    } else if (!query) {
      params.set("host", host);   // 默认只查当前站点，绝不摊开全部
    }
    let data;
    try {
      data = await api("/api/bridge/entries?" + params.toString());
    } catch (e) {
      if (e.message === "locked") return lockedView();
      return offlineView();
    }
    render(data.entries || [], query);
  }

  function render(entries, query) {
    $list.innerHTML = "";
    if (!entries.length) {
      const hint = query ? "无匹配结果"
        : catFilter ? "该分类下暂无条目"
        : "当前网站没有已保存的账号";
      $list.innerHTML = `<div class="state" style="padding:18px">${hint}</div>`;
      return;
    }
    for (const e of entries) {
      const [icon, color] = TYPE_ICON[e.type] || ["🔒", "#4c7dff"];
      const div = document.createElement("div");
      div.className = "entry";
      div.innerHTML = `
        <div class="badge" style="background:${color}22;border:1px solid ${color}55">${icon}</div>
        <div class="info">
          <div class="title">${esc(e.title)}</div>
          <div class="sub">${esc(e.username || e.host)}</div>
        </div>
        <div class="acts">
          <button class="primary" data-act="fill">填充</button>
          <button data-act="copy" title="复制密码">密码</button>
          ${e.hasTotp ? `<button data-act="totp" title="复制验证码">2FA</button>` : ""}
        </div>`;
      div.querySelectorAll("button").forEach(btn => {
        btn.onclick = () => act(btn.dataset.act, e, btn);
      });
      $list.appendChild(div);
    }
  }

  async function act(action, entry, btn) {
    try {
      const cred = await api("/api/bridge/credentials", {
        method: "POST", body: JSON.stringify({ uuid: entry.uuid }),
      });
      if (action === "fill") {
        await chrome.tabs.sendMessage(currentTab.id, {
          type: "jianmi-fill", username: cred.username, password: cred.password,
        });
        toast("已填充");
        setTimeout(() => window.close(), 500);
      } else if (action === "copy") {
        await navigator.clipboard.writeText(cred.password);
        btn.classList.add("ok"); btn.textContent = "✓";
        toast("已复制密码");
        setTimeout(() => { btn.classList.remove("ok"); btn.textContent = "密码"; }, 1200);
      } else if (action === "totp" && cred.totp) {
        await navigator.clipboard.writeText(cred.totp);
        toast("已复制验证码 " + cred.totp);
      }
    } catch (e) {
      toast(action === "fill" ? "填充失败（刷新页面后重试）" : "操作失败");
    }
  }

  // 搜索
  let timer;
  $search.oninput = () => {
    clearTimeout(timer);
    timer = setTimeout(() => load($search.value.trim()), 150);
  };

  // 保存表单
  const $form = document.getElementById("saveForm");
  document.getElementById("toggleSave").onclick = () => {
    $form.classList.toggle("show");
    if ($form.classList.contains("show")) {
      document.getElementById("sTitle").value = currentTab?.title
        ? hostName(host) : "";
      document.getElementById("sUser").focus();
    }
  };
  document.getElementById("sCancel").onclick = () => $form.classList.remove("show");
  document.getElementById("sGen").onclick = () => {
    document.getElementById("sPwd").value = generatePassword();
    document.getElementById("sPwd").type = "text";
  };
  document.getElementById("sGo").onclick = async () => {
    try {
      await api("/api/bridge/save", {
        method: "POST",
        body: JSON.stringify({
          title: document.getElementById("sTitle").value.trim(),
          url: currentTab?.url || "",
          username: document.getElementById("sUser").value.trim(),
          password: document.getElementById("sPwd").value,
        }),
      });
      toast("已保存到简密");
      $form.classList.remove("show");
      load("");
    } catch (e) {
      toast("保存失败");
    }
  };

  load("");
}

function hostName(host) {
  const parts = host.replace(/^www\./, "").split(".");
  const core = parts.length >= 2 ? parts[parts.length - 2] : host;
  return core.charAt(0).toUpperCase() + core.slice(1);
}

function generatePassword(len = 20) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*-_=+?";
  const buf = new Uint32Array(len);
  crypto.getRandomValues(buf);
  return [...buf].map(n => chars[n % chars.length]).join("");
}

// ── 入口 ─────────────────────────────────────────────────
async function init() {
  ({ token = "" } = await chrome.storage.local.get("token"));
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  currentTab = tab;

  if (!token) return pairingView();
  let status;
  try {
    status = await api("/api/bridge/status");
  } catch (e) {
    if (e.message === "unauthorized") return pairingView("令牌已失效，请重新配对");
    return offlineView();
  }
  if (status.locked) return lockedView();
  mainView();
}

init();
