import ApplicationServices
import CoreGraphics
import Foundation

/// 自动键入：把密码直接"打"进前台应用（CGEvent，需要辅助功能权限）。
/// 简密面板是非激活浮窗 —— 隐藏面板后前台 App 焦点未变，直接键入即可。
enum AutoTyper {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 弹出系统授权引导（系统设置 → 隐私与安全性 → 辅助功能）。
    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// 延迟一拍再键入，等面板完全隐藏、焦点回到目标输入框。
    static func type(_ text: String, after delay: TimeInterval = 0.2) {
        guard isTrusted else {
            requestPermission()
            return
        }
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + delay) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for scalar in text.unicodeScalars {
                var utf16 = Array(String(scalar).utf16)
                if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                    down.post(tap: .cghidEventTap)
                }
                if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                    up.post(tap: .cghidEventTap)
                }
                usleep(4000)   // 4ms/字符，兼容慢速输入框
            }
        }
    }
}
