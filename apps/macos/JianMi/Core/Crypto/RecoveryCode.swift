import Foundation

/// 恢复码：VaultKey（32 字节）的人类可抄写编码。
/// 这是忘记主密码时的唯一逃生通道（无后门是特性，见 DESIGN.md §1）。
///
/// v1 格式：64 位大写十六进制，分 8 组，如
///   `A1B2C3D4-E5F60718-...`（组间用 - 分隔，抄写时忽略大小写与分隔符）
enum RecoveryCode {
    static func encode(_ key: [UInt8]) -> String {
        let hex = key.map { String(format: "%02X", $0) }.joined()
        var groups: [String] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let end = hex.index(idx, offsetBy: 8, limitedBy: hex.endIndex) ?? hex.endIndex
            groups.append(String(hex[idx..<end]))
            idx = end
        }
        return groups.joined(separator: "-")
    }

    static func decode(_ code: String) -> [UInt8]? {
        let cleaned = code.uppercased().filter { $0.isHexDigit }
        guard cleaned.count == CryptoEngine.keyLength * 2 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(CryptoEngine.keyLength)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        return bytes
    }
}
