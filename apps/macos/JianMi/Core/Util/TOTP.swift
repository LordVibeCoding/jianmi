import CryptoKit
import Foundation

/// RFC 6238 TOTP 验证码生成（HMAC-SHA1 / 6 位 / 30 秒）。
enum TOTP {
    static let period: TimeInterval = 30

    /// 支持纯 base32 或 otpauth:// 链接。
    static func normalizeSecret(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("otpauth://"),
           let comps = URLComponents(string: s),
           let secret = comps.queryItems?.first(where: { $0.name.lowercased() == "secret" })?.value {
            s = secret
        }
        return s.replacingOccurrences(of: " ", with: "").uppercased()
    }

    static func code(secret: String, at date: Date = Date(), digits: Int = 6) -> String? {
        guard let key = base32Decode(normalizeSecret(secret)), !key.isEmpty else { return nil }
        var counter = UInt64(date.timeIntervalSince1970 / period).bigEndian
        let counterData = Data(bytes: &counter, count: 8)

        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: counterData, using: SymmetricKey(data: Data(key)))
        let bytes = Array(mac)
        let offset = Int(bytes[bytes.count - 1] & 0x0F)
        let truncated = (UInt32(bytes[offset] & 0x7F) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        let code = truncated % UInt32(pow(10, Double(digits)))
        return String(format: "%0\(digits)d", code)
    }

    /// 当前周期剩余秒数（0..30）。
    static func remainingSeconds(at date: Date = Date()) -> Double {
        period - date.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
    }

    // ── Base32 (RFC 4648) ────────────────────────────────
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func base32Decode(_ string: String) -> [UInt8]? {
        let cleaned = string.filter { $0 != "=" }
        var bits = 0, value = 0
        var output: [UInt8] = []
        for char in cleaned {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                output.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return output
    }
}
