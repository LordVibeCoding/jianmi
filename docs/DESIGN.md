# 简密（JianMi）设计文档

> 状态：定稿 v1 · 2025-06
> 本文档是整个项目的单一事实来源（Single Source of Truth），所有实现以此为准。

---

## 0. 第一性原理

把"密码管理器"剥到最底层，只有三件事：

1. **一个加密的键值库** —— 推导出：零知识安全模型，密钥永不落盘，密文之外什么都不给服务器
2. **极快的"存"与"取"** —— 推导出：唤起→保存 < 5s，搜索→复制 < 2s，窗口唤起 < 100ms → 必须原生
3. **数据主权** —— 推导出：自己的服务器 + 条目级"永不出本机"开关 + 明文可导出（不被自己软件绑架）

一切功能与技术决策都必须能回溯到这三条，否则砍掉。

---

## 1. 威胁模型（先想清楚防谁）

| 威胁 | 对策 |
|---|---|
| 服务器被攻破 / 服务商窥探 | 零知识：服务器只存密文 blob，无法解密 |
| 传输被窃听 | 载荷本身是密文；HTTPS/自签证书可选加固 |
| API token 泄露 | token 只能拿到密文；可随时轮换 |
| Mac 被盗（关机态） | 本地库字段级加密，无主密码无法解密 |
| Mac 被盗（解锁态短暂离开） | 自动锁定（超时/睡眠/锁屏触发），内存密钥清零 |
| 剪贴板嗅探 | NSPasteboard `concealed` 类型 + 30s 自动清空 |
| 钱包助记词级资产 | `local_only` 条目物理不进同步队列；可选 Secure Enclave 二次包裹 |
| 自己忘记主密码 | 无后门（这是特性）。提供纸质恢复码（VaultKey 的 BIP39 风格编码）打印存保险柜 |

**不防**：本机被植入内核级木马/键盘记录器（任何软件都防不了）、物理胁迫。

---

## 2. 加密架构

```
                     ┌─ 仅存内存，锁定即清零
主密码 ──Argon2id──▶ MasterKey (256bit)
 (m=64MB,t=3,p=4)        │ XChaCha20-Poly1305 解密
                         ▼
                    VaultKey (随机256bit) ←── 密文形式落盘 / 纸质恢复码
                         │
            ┌────────────┼─────────────┐
            ▼            ▼             ▼
        条目1密文      条目2密文    附件密文
   (每条目独立 nonce，AEAD 附加数据 = uuid+version 防重放/调包)
```

### 决策点

- **KDF：Argon2id**（libsodium 提供），参数 memory=64MB / iterations=3 / parallelism=4，登录耗时目标 ~500ms
- **对称加密：XChaCha20-Poly1305**（libsodium）。24 字节 nonce 随机生成无碰撞之忧；AEAD 自带完整性认证
- **两层密钥的意义**：改主密码只需重新加密 VaultKey（1 条记录），不用重加密全库
- **便捷解锁**：VaultKey 经 Secure Enclave 密钥包裹后存 Keychain（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `biometryCurrentSet`）→ 平时 Touch ID 秒开；重启 / 超过 N 小时 / 手动锁定后要求主密码
- **恢复码**：VaultKey 编码为 24 个单词，首次建库时强制展示一次并建议打印。丢主密码时用恢复码 + 新主密码重建
- **内存卫生**：密钥用 `SecureBytes`（mlock + 析构清零），锁定时立即清零；SwiftUI 层不持有明文密码字符串引用

### 加密格式（版本化，为未来算法升级留门）

```
blob = magic(2B "JM") | fmt_ver(1B) | nonce(24B) | ciphertext+tag
```

---

## 3. 数据模型

### 条目（Entry）

```
Entry {
  uuid:        UUIDv7                  // 明文，时间有序利于同步
  type:        网站|App|银行卡|钱包(强制local_only)|SSH|证件|笔记|自定义
  title:       String                  // 明文（用于索引/列表/搜索）
  url_host:    String?                 // 明文，仅域名部分（用于匹配/图标）
  tags:        [String]                // 明文
  local_only:  Bool                    // true = 永不进同步队列
  favorite:    Bool
  version:     Int                     // 每次修改 +1
  updated_at / created_at / deleted_at(墓碑)

  secret_blob: Encrypted<SecretBody>   // 以下全部密文：
}

SecretBody {
  username, password, url_full, totp_secret,
  custom_fields: [{label, value, kind: text|hidden|url}],
  notes_markdown: String,
  password_history: [{value, changed_at}]   // 自动保留旧密码
}
```

**明文/密文边界原则**：列表展示与搜索所需的最小集合（标题、域名、标签、类型）明文；一切"值"（账号、密码、URL 全文、笔记）密文。接受"条目标题可被本机攻击者看到"的取舍换取免解锁即时搜索。若未来想要更强隐私，加"隐身条目"选项（标题也加密，仅解锁后可搜）。

### 本地存储

- SQLite via **GRDB.swift**，WAL 模式
- `entries` 表 + **FTS5** 虚拟表（title/url_host/tags）→ 万条数据毫秒级模糊搜索
- 附件单独表，密文 blob 存磁盘文件、库内存引用（避免库膨胀）
- 全库定期自动备份到本地加密快照（保留最近 N 份，防误删/防同步事故）

---

## 4. 同步协议（自研，因为零知识下它极简）

### 为什么不用现成的

- **Vaultwarden**：服务端优秀，但客户端协议 = 实现整套 Bitwarden API（复杂度远超自研协议），且官方 mac 客户端是 Electron，不满足性能与快速捕获需求
- **KDBX + WebDAV**：整库文件级同步，多端冲突只能整库二选一，无法做条目级合并；且无自然的 Web 查看方案
- 自研协议在零知识前提下只是"密文 blob 增量仓库"，服务端 ~500 行 Rust

### 协议设计

服务器维护单调递增全局序号 `seq`，每次任何条目变更 seq+1 并记录到该条目。

```
POST /api/sync/pull   { since_seq }            → 返回 seq > since_seq 的全部条目密文+元数据
POST /api/sync/push   { entries: [...] }       → 服务器校验 version 单调，接受则分配新 seq
POST /api/token/rotate                         → 轮换 API token
GET  /api/health
```

- **鉴权**：`Authorization: Bearer <64字节随机token>`，token 存客户端 Keychain；可选 IP 白名单
- **冲突**：version 冲突时服务器拒绝该条，客户端拉最新→ 字段级三方合并（合不了则 LWW + 自动保留"冲突副本"条目，永不静默丢数据）
- **删除**：墓碑标记，90 天后服务端物理清除
- **local_only 条目**：客户端同步引擎入口处硬过滤，代码路径上物理到不了网络层
- **服务端存储**：单文件 SQLite —— 备份 = 复制一个文件

---

## 5. macOS 客户端

### 5.1 窗口体系

| 窗口 | 实现 | 触发 | 行为 |
|---|---|---|---|
| 快速捕获 | `NSPanel`(nonactivating, floating) + SwiftUI | 全局 ⌥⌘N | 自动预填当前浏览器 URL/标题，Tab 流转字段，回车保存即消失。目标全程 <5s |
| 快速搜索 | 同上，Spotlight 式 | 全局 ⌥⌘P | 输入即搜（FTS5），回车复制密码，⌘回车 Auto-Type，→ 展开详情 |
| 主窗口 | 标准 `NSWindow` + SwiftUI 三栏 | 菜单栏/Dock/⌘1 | 分类·标签 / 条目列表 / 详情（字段+Markdown 笔记实时渲染） |
| 悬浮小窗 | `NSPanel` 可钉住置顶 | 从详情"钉住" | 迷你只读视图（抄激活码/助记词场景） |
| 菜单栏 | `NSStatusItem` + MenuBarExtra | 常驻 | 锁定状态指示、快速搜索入口、锁定/设置 |

- App 以 **LSUIElement**（无 Dock 图标的 Agent）模式常驻，打开主窗口时临时显示 Dock 图标
- 快速捕获的 URL 预填：AppleScript/Apple Events 读取 Safari/Chrome/Arc/Edge 前台标签页（首次触发"自动化"授权弹窗，拒绝则优雅降级为手输）

### 5.2 关键依赖（避免造轮子）

| 库 | 用途 | 备注 |
|---|---|---|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 全局快捷键 | Carbon RegisterEventHotKey 封装，**无需辅助功能权限**，带偏好设置录制 UI |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite + FTS5 | Swift 生态最成熟 |
| [swift-sodium](https://github.com/jedisct1/swift-sodium) | Argon2id / XChaCha20 | libsodium 官方绑定 |
| [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) | 笔记渲染 | GFM 支持 |
| CryptoKit / LocalAuthentication / SMAppService | 系统能力 | 系统自带 |
| TOTP | 自实现 | RFC 6238 约 30 行，不值得引库 |

### 5.3 权限矩阵（结论：MVP 零权限弹窗）

| 能力 | 权限 | 阶段 |
|---|---|---|
| 全局快捷键 / 菜单栏 / 浮窗 / 开机自启 / Touch ID / 剪贴板 | **无需任何授权** | M1-M2 |
| 抓浏览器当前 URL | 自动化(Apple Events)，首次弹窗 | M2（可拒绝降级） |
| Auto-Type 模拟键入 | 辅助功能 | M5 可选 |
| 系统级自动填充 | `ASCredentialProviderExtension` + Apple 开发者账号 entitlement，扩展强制沙盒 | M5 |
| 分发 | **已决策：无开发者账号，本地编译 ad-hoc 签名自用**；系统 AutoFill 扩展因此不可用，以 Auto-Type + 快速搜索复制替代 | — |

### 5.4 安全行为

- 自动锁定：可配置超时 / 睡眠 / 锁屏 / 快速切换用户 → 立即清密钥
- 剪贴板：`org.nspasteboard.ConcealedType` 标记 + 30s 定时清空（仅当剪贴板内容仍是我们放的才清）
- 窗口防截屏：详情窗 `sharingType = .none`（屏幕共享时不可见，可开关）
- 密码生成器：长度/字符集/易读模式/passphrase（diceware）模式

---

## 6. 服务端（Rust）

- **axum + rusqlite**，单二进制，`selfvault-server --config config.toml`
- config：监听地址端口、token hash（服务端只存 token 的 SHA-256）、数据目录、可选 TLS 证书路径、可选 IP 白名单
- 同时托管 `web/` 静态文件
- 部署：scp 一个二进制 + systemd unit（scripts/ 提供模板）；无 Docker 依赖（也提供 Dockerfile 备选）
- 资源占用目标：< 10MB 内存

## 7. Web 端（只读优先）

- 纯静态：原生 JS + libsodium.js + argon2 wasm，无框架无构建链
- 流程：输 token 拉密文清单 → 输主密码浏览器内派生解密 → 搜索/查看/复制
- 密钥只存 sessionStorage 之外的内存变量，标签页关闭即失
- v1 只读（够用且攻击面小），编辑能力视需求后置

---

## 8. 里程碑与验收标准

> 进度：M0-M4 已完成 ✅（含 M5 部分：TOTP/Auto-Type/改主密码/自定义字段/密码历史）。
> 跨语言加密兼容性（Swift 加密 → 浏览器 JS 解密）由 scripts/verify_web_crypto.mjs 自动化验证。

### M0 —— 仓库与设计 ✅
Git + GitHub 私仓 + 本文档

### M1 —— 核心（可用的本地密码库）
Xcode 工程（SwiftUI, LSUIElement）；加密引擎 + 单元测试（KDF/AEAD 测试向量）；GRDB 库表 + FTS5；建库流程（主密码+恢复码）；解锁（主密码 + Touch ID）；主窗口三栏 CRUD；Markdown 笔记；密码生成器；自动锁定
**验收**：建库→存 50 条→锁定→Touch ID 解锁→搜索复制，全流程顺畅；重启后数据完好；DB 文件用 sqlite3 打开看不到任何明文机密

### M2 —— 效率（核心体验）
⌥⌘N 快速捕获（浏览器 URL 预填）；⌥⌘P 快速搜索；菜单栏；剪贴板安全；开机自启
**验收**：注册新网站场景 —— 按键→预填→输账号→生成密码→回车，≤ 5 秒；唤起延迟肉眼无感（<100ms）

### M3 —— 同步
Rust 服务端 + pull/push + token 鉴权；客户端同步引擎（增量、冲突副本、local_only 过滤）；多设备测试
**验收**：两台 Mac 双向同步一致；同条目双端并发改不丢数据；local_only 条目在服务器 DB 中 grep 不到任何痕迹；抓包只见密文

### M4 —— Web
静态页 + 浏览器内解密只读视图
**验收**：手机/其他电脑浏览器 `ip:port` + token + 主密码可查密码；服务器磁盘与网络层全程零明文

### M5 —— 进阶（按需排序）
系统 AutoFill 扩展 / TOTP / Auto-Type / 附件 / 安全审计（弱密码·重复密码·可选 HIBP 泄露检查 k-anonymity 模式）/ 导入导出（CSV/1Password/Bitwarden 格式）/ 签名公证

---

## 9. 已决策事项备忘（防止未来反复）

1. **不用 Electron/Tauri** —— 窗口唤起速度与原生浮窗行为是硬需求
2. **不接 Bitwarden/Vaultwarden 生态** —— 协议实现成本 > 自研零知识同步
3. **不用整库文件同步（KDBX/WebDAV）** —— 需要条目级合并
4. **标题/域名/标签明文** —— 换取免解锁即时搜索，未来可加"隐身条目"
5. **服务端只存 token 哈希与密文** —— 被攻破即最坏情况也只丢密文
6. **无密码找回后门** —— 恢复码是唯一逃生通道，这是特性
7. **Web 端 v1 只读** —— 收缩攻击面
