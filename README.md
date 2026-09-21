# 简密 JianMi

> 简单记录你的密码，但你的密码将会 100% 的安全。
> 自托管 · 零知识加密 · 原生 macOS 密码管理器

## 这是什么

一个为个人打造的密码/机密管理器（纯本地编译自用，不上架 App Store，无需开发者账号）：

- **原生 macOS App**：菜单栏常驻、全局快捷键唤起、Spotlight 式快速捕获/搜索浮窗、三栏主窗口、可钉住悬浮小窗
- **自托管同步**：数据同步到自己的服务器（Rust 单二进制），零知识 —— 服务器只见密文
- **选择性同步**：钱包助记词等敏感条目可标记 `local_only`，物理上永不出本机
- **简易 Web 页**：`ip:端口 + token` 访问，浏览器内输入主密码本地解密（WebCrypto），服务器始终零知识
- **Markdown 笔记**：每个条目 = 结构化字段（账号/密码/URL/TOTP/自定义字段）+ Markdown 富文本笔记

## 技术栈

| 层 | 选型 | 理由 |
|---|---|---|
| macOS 客户端 | Swift 6 + SwiftUI/AppKit | 冷启动 <100ms、NSPanel 非激活浮窗、Touch ID/Secure Enclave、系统 AutoFill 均为原生独占 |
| 本地存储 | SQLite (GRDB) + 字段级加密 | 标题/URL/标签建 FTS5 全文索引即时搜索，敏感字段全密文 |
| 加密 | Argon2id + XChaCha20-Poly1305 | 主密码派生 MasterKey → 解密 VaultKey → 条目级加密 |
| 同步服务端 | Rust (axum) | 单二进制、几 MB 内存、零运行时依赖 |
| Web 端 | 静态页 + libsodium.js/argon2-wasm | 浏览器内解密，服务器零知识 |

## 快速上手

### macOS App（无需开发者账号）

```bash
brew install xcodegen          # 首次
cd apps/macos
xcodegen generate              # 生成 JianMi.xcodeproj
open JianMi.xcodeproj          # Xcode 中 ⌘R 运行，或：
xcodebuild -scheme JianMi build
xcodebuild -scheme JianMi test # 跑全部单元测试
```

**全局快捷键**（可在设置中自定义）：
- `⌥⌘N` 快速捕获 —— 浏览器当前网址自动预填（由扩展上报，零权限），填账号密码回车即存
- `⌥⌘P` 快速搜索 —— ↩复制密码 / ⌥↩复制账号 / ⌘↩打开网址 / ⌃↩自动键入

### 浏览器扩展（Chrome / Edge / Arc / Brave）

与本地 App 通过 `127.0.0.1:48787` 桥接（配对令牌鉴权，外网不可达）：

1. 打开 `chrome://extensions` → 开启「开发者模式」→「加载已解压的扩展程序」→ 选 `extension/` 目录
2. 简密 App → 设置 → 浏览器扩展 → 复制配对令牌 → 粘到扩展里
3. 之后：点扩展图标可**一键填充**当前网站账号密码 / 复制密码和 2FA 验证码 / 保存新账号；扩展实时上报当前标签页，⌥⌘N 无需任何系统权限即可预填网址

### 同步服务端（自己的服务器）

```bash
cd server && cargo build --release
./target/release/jianmi-server --addr 0.0.0.0:8787 --data ./data
# 首次启动打印访问令牌 → 填入 App 设置→同步；浏览器访问同地址即 Web 视图

# 或一键部署到 Linux 服务器（含 systemd 守护）：
./scripts/deploy_server.sh user@your-server-ip
```

## 仓库结构

```
├── docs/           设计文档（先读 docs/DESIGN.md）
├── apps/macos/     macOS 客户端（Swift/SwiftUI，xcodegen 工程）
├── extension/      浏览器扩展（Manifest V3，与本地 App 桥接）
├── server/         Rust 同步服务端（单二进制，零知识）
├── web/            静态 Web 只读视图（浏览器内解密）
└── scripts/        构建/部署/验证脚本
```

## 路线图

- [x] **M0** 仓库初始化 + 完整设计文档
- [x] **M1** 核心：加密引擎、本地库、主窗口 CRUD、主密码 + Touch ID 解锁
- [x] **M2** 效率：全局快捷键、快速捕获（⌥⌘N + 浏览器网址抓取）、快速搜索（⌥⌘P）、菜单栏、剪贴板安全、设置窗口、钉住悬浮窗
- [x] **M3** 同步：Rust 服务端、token 鉴权、条目级增量同步、冲突副本、local_only 硬隔离
- [x] **M4** Web：浏览器内解密只读视图（跨语言加密兼容性已由自动化验证）
- [x] **M5（部分）** TOTP 两步验证码、Auto-Type 自动键入、改主密码、自定义字段、密码历史
- [ ] **待办** 附件、安全审计（弱密码/重复检测）、导入导出（系统 AutoFill 需开发者账号，已用 Auto-Type 替代）

详细设计见 [docs/DESIGN.md](docs/DESIGN.md)。
