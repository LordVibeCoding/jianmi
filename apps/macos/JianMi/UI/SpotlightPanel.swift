import AppKit
import SwiftUI

/// Spotlight 式非激活浮动面板：
/// - 不抢占前台 App 焦点（nonactivatingPanel），但可接收键盘输入
/// - 失焦自动消失、Esc 关闭、所有空间可见
final class FloatingPanel: NSPanel {
    var onClose: (() -> Void)?
    /// Touch ID 等系统弹窗期间抑制"失焦即关"
    var suppressAutoClose = false

    init(width: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { close_() }

    override func resignKey() {
        super.resignKey()
        if !suppressAutoClose { close_() }
    }

    private func close_() {
        orderOut(nil)
        onClose?()
    }
}

/// 面板控制器：管理生命周期与屏幕定位。
@MainActor
final class SpotlightPanelController {
    private var panel: FloatingPanel?
    private let width: CGFloat

    init(width: CGFloat) { self.width = width }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(_ view: AnyView) {
        hide()
        let panel = FloatingPanel(width: width)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting
        panel.onClose = { [weak self] in self?.panel = nil }

        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(NSSize(width: width, height: max(size.height, 80)))

        // 定位：主屏水平居中，垂直偏上（Spotlight 位置）
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let x = f.midX - width / 2
            let y = f.minY + f.height * 0.62
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    func toggle(_ view: @autoclosure () -> AnyView) {
        if isVisible { hide() } else { show(view()) }
    }

    /// Touch ID 等系统弹窗前调用，防止面板因失焦关闭。
    func beginSystemPrompt() { panel?.suppressAutoClose = true }
    func endSystemPrompt() {
        panel?.suppressAutoClose = false
        panel?.makeKeyAndOrderFront(nil)
    }
}
