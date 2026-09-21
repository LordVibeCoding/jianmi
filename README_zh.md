# 简密 JianMi

[English](README.md) | **简体中文**

> 简单记录你的密码，但你的密码将会 100% 安全。

自托管 · 零知识加密的密码管理器：原生 macOS App + 浏览器扩展 + Rust 同步服务端 + 浏览器内解密的 Web 密码库。

## 亮点

- 🖥 **原生 macOS App**（Swift/SwiftUI）—— 菜单栏常驻、毫秒级冷启动、约 30MB 内存，拒绝 Electron
- ⚡️ **全局快捷键** —— `⌥⌘N` Spotlight 式快速捕获（浏览器网址自动预填），`⌥⌘P` 快速搜索：回车复制密码全程不到 2 秒
- 🧩 **浏览器扩展**（Chrome / Edge / Arc / Brave / Firefox）—— 一键填充、复制 2FA 验证码、保存新账号；仅通过 `127.0.0.1` 与 App 通信，配对令牌鉴权
- 🔐 **零知识加密** —— Argon2id + XChaCha20-Poly1305，主密码永不离开内存；服务器、网络、甚至你的磁盘上只有密文
- ☁️ **自托管同步** —— Rust 单二进制服务端（约 10MB 内存），条目级增量同步 + 冲突副本，永不静默丢数据
- 🏠 **仅本机条目** —— 钱包助记词等敏感信息标记「仅本机」后物理上进不了同步管道（代码层强制，钱包类条目强制开启）
- 🌐 **Web 密码库** —— 浏览器打开 `http://你的服务器:8787`，输入令牌 + 主密码，**解密只发生在浏览器内**（libsodium.js），服务器始终零知识
- 🔑 触控 ID 解锁、TOTP 验证码生成、自动键入、密码生成器与历史、Markdown 笔记、可钉住悬浮窗、自动锁定、剪贴板自动清除

## 安装

### macOS App

去 [Releases](https://github.com/LordVibeCoding/jianmi/releases/latest) 下载 `JianMi-x.y.z.dmg`，把 **JianMi** 拖进 **Applications** 即可。

> 无 Apple 开发者账号，采用 ad-hoc 签名。首次打开请 **右键 → 打开**，或执行 `xattr -cr /Applications/JianMi.app`。

或从源码构建：

```bash
brew install xcodegen
cd apps/macos && xcodegen generate
xcodebuild -scheme JianMi -configuration Release build   # 或 Xcode 里 ⌘R
```

### 浏览器扩展

App 内：**设置 → 浏览器扩展 → 导出扩展包**，然后：

- **Chrome / Edge / Arc / Brave**：解压 → `chrome://extensions` → 开启「开发者模式」→「加载已解压的扩展程序」
- **Firefox**：`about:debugging` →「此 Firefox」→「临时加载附加组件」→ 选 zip
  （长期使用建议 Firefox Developer Edition，设置 `xpinstall.signatures.required = false`）

把同一设置页里的配对令牌粘进扩展，完成。

### 同步服务端（自己的服务器）

```bash
cd server && cargo build --release
./target/release/jianmi-server --addr 0.0.0.0:8787 --data ./data
# 首次启动打印访问令牌 → 填入 App 设置 → 同步
# 同一地址在浏览器打开就是 Web 密码库
```

一条命令部署到 Linux 服务器（musl 静态二进制 + 加固 systemd）：

```bash
./scripts/deploy_server.sh user@你的服务器
```

## 安全模型

| 威胁 | 防御 |
|---|---|
| 服务器被攻破 | 零知识：服务器只存 `uuid + 版本号 + 密文` |
| 网络窃听 | 载荷离开设备前已是密文 |
| 令牌泄露 | 令牌只能拿到密文，可随时轮换 |
| Mac 被盗（锁定态） | 字段级加密，无主密码无法解密任何内容 |
| 临时离开电脑 | 锁屏/睡眠/空闲自动锁定，密钥内存清零（memzero） |
| 剪贴板嗅探 | concealed 标记 + 30 秒自动清除 |
| 钱包助记词级资产 | `local_only` 条目在代码层到不了网络层 |
| 忘记主密码 | 无后门（这是特性）；一次性恢复码是唯一逃生通道 |

**密钥链**：主密码 → Argon2id（64MB, t=3）→ MasterKey → 解包 → VaultKey → 条目级 XChaCha20-Poly1305 AEAD（AAD = 条目 UUID，防密文调包）。跨语言兼容性（Swift 加密 → 浏览器 JS 解密）由自动化测试保障（`scripts/verify_web_crypto.mjs`）。

## 架构

```
┌── macOS App (Swift) ──┐   127.0.0.1:48787   ┌── 浏览器扩展 ──┐
│ SQLite + FTS5         │ ←── 配对令牌 ──────→ │ 填充 / 保存    │
│ 加密核心 (sodium)     │                      └───────────────┘
│ 同步引擎              │
└──────────┬────────────┘
           │  HTTPS/HTTP —— 只有密文
           ▼
┌── Rust 服务端（axum，单二进制）──┐
│ 增量同步存储 (SQLite)           │──► Web 密码库（浏览器内解密）
└─────────────────────────────────┘
```

完整设计文档：[docs/DESIGN.md](docs/DESIGN.md)

## 仓库结构

```
├── apps/macos/     macOS 客户端（SwiftUI，xcodegen 工程）
├── extension/      浏览器扩展（Manifest V3）
├── server/         Rust 同步服务端
├── web/            静态 Web 密码库（浏览器内解密）
├── scripts/        构建 / 部署 / 验证脚本
└── docs/           设计文档
```

## 开发

```bash
# macOS 测试（17 项：加密向量、库生命周期、磁盘明文泄露检测、TCP 回环桥接）
cd apps/macos && xcodebuild -scheme JianMi test

# 跨语言加密验证（Swift → JS）
node scripts/verify_web_crypto.mjs

# 服务端
cd server && cargo build --release

# 分发产物（DMG + 扩展包）
./scripts/build_dmg.sh
```

## 许可证

[MIT](LICENSE)
