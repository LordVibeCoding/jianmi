import AppKit

/// 安全剪贴板：
/// 1. 标记 org.nspasteboard.ConcealedType —— 剪贴板管理器（Alfred/Raycast 等）不记录
/// 2. 30 秒后自动清空（仅当剪贴板内容仍是我们放入的那份）
enum SecurePasteboard {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    static func copy(_ string: String, clearAfter seconds: TimeInterval = 30) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("1", forType: concealedType)
        pb.setString(string, forType: .string)

        let change = pb.changeCount
        guard seconds > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if NSPasteboard.general.changeCount == change {
                NSPasteboard.general.clearContents()
            }
        }
    }
}
