# JianMi 简密

**English** | [简体中文](README_zh.md)

> Simply record your passwords — and keep them 100% safe.

A self-hosted, zero-knowledge password manager built natively for macOS, with a browser extension, a Rust sync server, and an in-browser web vault.

## Highlights

- 🖥 **Native macOS app** (Swift/SwiftUI) — menu bar resident, cold start in milliseconds, ~30 MB RAM. No Electron.
- ⚡️ **Global hotkeys** — `⌥⌘N` Spotlight-style quick capture (URL prefilled from your browser), `⌥⌘P` quick search: hit Enter to copy a password in under 2 seconds.
- 🧩 **Browser extension** (Chrome / Edge / Arc / Brave / Firefox) — one-click autofill, copy 2FA codes, and save new logins. Talks to the app over `127.0.0.1` only, paired with a token.
- 🔐 **Zero-knowledge encryption** — Argon2id + XChaCha20-Poly1305. Your master password never leaves RAM; the server, the network, and even your disk only ever see ciphertext.
- ☁️ **Self-hosted sync** — a single-binary Rust server (~10 MB RAM). Entry-level incremental sync with conflict copies; nothing is ever silently lost.
- 🏠 **Local-only entries** — mark wallet seeds & sensitive secrets as *local-only*: they physically never enter the sync pipeline (enforced in code, wallet-type entries are forced).
- 🌐 **Web vault** — open `http://your-server:8787`, enter your token + master password, and decrypt *inside the browser* (libsodium.js). The server stays zero-knowledge.
- 🔑 **Touch ID unlock**, TOTP (2FA) generator, auto-type, password generator & history, Markdown notes, pinnable floating windows, auto-lock, clipboard auto-clear.

## Install

### macOS App

Grab `JianMi-x.y.z.dmg` from [Releases](https://github.com/LordVibeCoding/jianmi/releases/latest), drag **JianMi** into **Applications**.

> Builds are ad-hoc signed (no Apple Developer account). On first launch: **right-click → Open**, or run `xattr -cr /Applications/JianMi.app`.

Or build from source:

```bash
brew install xcodegen
cd apps/macos && xcodegen generate
xcodebuild -scheme JianMi -configuration Release build   # or open in Xcode → ⌘R
```

### Browser extension

Inside the app: **Settings → Browser Extension → Export extension pack**, then:

- **Chrome / Edge / Arc / Brave**: unzip → `chrome://extensions` → enable *Developer mode* → *Load unpacked*
- **Firefox**: `about:debugging` → *This Firefox* → *Load Temporary Add-on* → pick the zip
  (for permanent install use Firefox Developer Edition with `xpinstall.signatures.required = false`)

Paste the pairing token from the same settings page into the extension. Done.

### Sync server (your own box)

```bash
cd server && cargo build --release
./target/release/jianmi-server --addr 0.0.0.0:8787 --data ./data
# First run prints an access token → paste into App Settings → Sync.
# The same address serves the web vault in any browser.
```

One-command deploy to a Linux host (static musl binary + hardened systemd unit):

```bash
./scripts/deploy_server.sh user@your-server
```

## Security model

| Threat | Defense |
|---|---|
| Server breach | Zero-knowledge: server stores only `uuid + version + ciphertext` |
| Network sniffing | Payloads are ciphertext before they leave the device |
| Token leak | A token only yields ciphertext; rotate anytime |
| Stolen Mac (locked) | Field-level encryption; nothing decryptable without the master password |
| Walk-away Mac | Auto-lock on screen lock / sleep / idle; keys are zeroed (memzero) |
| Clipboard sniffers | Concealed pasteboard type + auto-clear after 30 s |
| Crypto-wallet secrets | `local_only` entries never reach the network layer, enforced in code |
| Forgotten master password | No backdoor (by design). A one-time recovery code is your only escape hatch |

**Key chain**: master password → Argon2id (64 MB, t=3) → MasterKey → unwraps → VaultKey → XChaCha20-Poly1305 per-entry AEAD (AAD = entry UUID, anti-swap). Cross-language compatibility (Swift encrypt → browser JS decrypt) is verified by an automated test (`scripts/verify_web_crypto.mjs`).

## Architecture

```
┌── macOS app (Swift) ──┐   127.0.0.1:48787   ┌─ Browser extension ─┐
│ SQLite + FTS5         │ ←── pairing token ──→│ autofill / save     │
│ crypto core (sodium)  │                      └─────────────────────┘
│ sync engine           │
└──────────┬────────────┘
           │  HTTPS/HTTP — ciphertext only
           ▼
┌── Rust server (axum, single binary) ──┐
│ incremental sync store (SQLite)       │──► Web vault (decrypts in-browser)
└───────────────────────────────────────┘
```

Full design doc (Chinese): [docs/DESIGN.md](docs/DESIGN.md)

## Repository layout

```
├── apps/macos/     macOS app (SwiftUI, xcodegen project)
├── extension/      Browser extension (Manifest V3)
├── server/         Rust sync server
├── web/            Static web vault (in-browser decryption)
├── scripts/        build / deploy / verification scripts
└── docs/           design documents
```

## Development

```bash
# macOS app tests (17 tests: crypto vectors, vault lifecycle,
# plaintext-leak-on-disk check, TCP loopback bridge tests)
cd apps/macos && xcodebuild -scheme JianMi test

# Cross-language crypto verification (Swift → JS)
node scripts/verify_web_crypto.mjs

# Server
cd server && cargo build --release

# Distribution artifacts (DMG + extension zips)
./scripts/build_dmg.sh
```

## License

[MIT](LICENSE)
