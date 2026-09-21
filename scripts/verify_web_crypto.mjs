// 跨语言加密验证：用 web/sodium.js（浏览器同款）解密 Swift 生成的夹具。
// 复刻 web/index.html 的解密逻辑，任何一步不匹配即失败。
// 用法: 先跑 WebFixtureTests 生成 /tmp/jianmi-web-fixture.json，再 node scripts/verify_web_crypto.mjs
import { readFileSync } from "fs";
import { createRequire } from "module";
import { fileURLToPath } from "url";

const require = createRequire(import.meta.url);
const path = fileURLToPath(new URL("../web/sodium.js", import.meta.url));
const sodiumModule = require(path);
const sodium = sodiumModule.default ?? sodiumModule;
await sodium.ready;

const fixture = JSON.parse(readFileSync("/tmp/jianmi-web-fixture.json", "utf8"));
const b64d = (s) => sodium.from_base64(s, sodium.base64_variants.ORIGINAL);

// ── 与 web/index.html 完全一致的 openBlob ──
function openBlob(blob, key, aad) {
  if (blob[0] !== 0x4a || blob[1] !== 0x4d || blob[2] !== 1) throw new Error("密文格式无效");
  const nonce = blob.slice(3, 3 + 24);
  const ct = blob.slice(3 + 24);
  return sodium.crypto_aead_xchacha20poly1305_ietf_decrypt(
    null, ct, aad ? sodium.from_string(aad) : null, nonce, key);
}

// 1. Argon2id 派生
const masterKey = sodium.crypto_pwhash(
  32, sodium.from_string(fixture.password), b64d(fixture.kdfSalt),
  fixture.kdfOpsLimit, fixture.kdfMemLimit, sodium.crypto_pwhash_ALG_ARGON2ID13);

// 2. 解开 VaultKey
const vaultKey = openBlob(b64d(fixture.wrappedVaultKey), masterKey, "jianmi.vaultkey.v1");

// 3. 解开同步载荷
const payload = JSON.parse(sodium.to_string(
  openBlob(b64d(fixture.payload), vaultKey, "sync:" + fixture.uuid)));

// 4. 解开内层 secretBlob
const secret = JSON.parse(sodium.to_string(
  openBlob(b64d(payload.secretBlob), vaultKey, fixture.uuid)));

// 断言
const assert = (cond, msg) => { if (!cond) { console.error("✗ " + msg); process.exit(1); } };
assert(payload.title === fixture.expected.title, `title 不匹配: ${payload.title}`);
assert(secret.username === fixture.expected.username, `username 不匹配: ${secret.username}`);
assert(secret.password === fixture.expected.password, `password 不匹配: ${secret.password}`);

// 5. 错误密码必须失败
let failed = false;
try {
  const wrongKey = sodium.crypto_pwhash(
    32, sodium.from_string("错误密码"), b64d(fixture.kdfSalt),
    fixture.kdfOpsLimit, fixture.kdfMemLimit, sodium.crypto_pwhash_ALG_ARGON2ID13);
  openBlob(b64d(fixture.wrappedVaultKey), wrongKey, "jianmi.vaultkey.v1");
} catch (e) { failed = true; }
assert(failed, "错误密码竟然解密成功！");

console.log("✓ 跨语言加密验证通过：Swift 加密 → 浏览器 JS 解密完全兼容");
console.log(`  payload.title = ${payload.title}, secret.username = ${secret.username}`);
