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

## 本地构建（无需开发者账号）

```bash
brew install xcodegen          # 首次
cd apps/macos
xcodegen generate              # 生成 JianMi.xcodeproj
open JianMi.xcodeproj          # Xcode 中 ⌘R 运行，或：
xcodebuild -scheme JianMi build
xcodebuild -scheme JianMi test # 跑全部单元测试
```

## 仓库结构

```
├── docs/           设计文档（先读 docs/DESIGN.md）
├── apps/macos/     macOS 客户端（Xcode 工程，M1 开始）
├── server/         Rust 同步服务端（M3 开始）
├── web/            静态 Web 只读视图（M4 开始）
└── scripts/        构建/部署脚本
```

## 路线图

- [x] **M0** 仓库初始化 + 完整设计文档
- [x] **M1** 核心：加密引擎、本地库、主窗口 CRUD、主密码 + Touch ID 解锁
- [ ] **M2** 效率：全局快捷键、快速捕获（⌥⌘N）、快速搜索（⌥⌘P）、菜单栏、剪贴板安全
- [ ] **M3** 同步：Rust 服务端、token 鉴权、条目级增量同步、local_only
- [ ] **M4** Web：浏览器内解密只读视图
- [ ] **M5** 进阶：系统 AutoFill 扩展、TOTP、Auto-Type、附件、安全审计

详细设计见 [docs/DESIGN.md](docs/DESIGN.md)。
