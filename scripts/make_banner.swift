// 生成 README 顶部 banner（深色 hero 图）
// 用法: swift scripts/make_banner.swift <输出目录>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let W: CGFloat = 1600, H: CGFloat = 500

let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()

// ── 背景：GitHub 深色 + 蓝色辉光 ──
NSColor(calibratedRed: 0.051, green: 0.067, blue: 0.09, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.3, green: 0.45, blue: 1.0, alpha: 0.22),
    NSColor(calibratedRed: 0.3, green: 0.45, blue: 1.0, alpha: 0.0),
])!
glow.draw(in: NSBezierPath(ovalIn: NSRect(x: 80, y: -200, width: 900, height: 900)),
          relativeCenterPosition: .zero)
let glow2 = NSGradient(colors: [
    NSColor(calibratedRed: 0.55, green: 0.35, blue: 1.0, alpha: 0.10),
    NSColor(calibratedRed: 0.55, green: 0.35, blue: 1.0, alpha: 0.0),
])!
glow2.draw(in: NSBezierPath(ovalIn: NSRect(x: 900, y: -100, width: 800, height: 800)),
           relativeCenterPosition: .zero)

// ── App 图标（渐变圆角方 + 白钥匙）──
func drawIcon(at origin: NSPoint, size: CGFloat) {
    let rect = NSRect(x: origin.x, y: origin.y, width: size, height: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedRed: 0.3, green: 0.45, blue: 1.0, alpha: 0.55)
    shadow.shadowBlurRadius = 44
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(calibratedRed: 0.35, green: 0.55, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.85, alpha: 1),
    ])!.draw(in: path, angle: -60)

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let sw = size * 0.42
        let sh = sw * (symbol.size.height / symbol.size.width)
        let cx = origin.x + size / 2, cy = origin.y + size / 2
        NSGraphicsContext.current?.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: cx, yBy: cy)
        t.rotate(byDegrees: -25)
        t.translateX(by: -cx, yBy: -cy)
        t.concat()
        symbol.draw(in: NSRect(x: cx - sw / 2, y: cy - sh / 2, width: sw, height: sh))
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
drawIcon(at: NSPoint(x: 150, y: (H - 220) / 2), size: 220)

// ── 文字 ──
func draw(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, kern: CGFloat = 0) {
    (text as NSString).draw(at: point, withAttributes: [
        .font: font, .foregroundColor: color, .kern: kern,
    ])
}

let textX: CGFloat = 470
draw("简密", at: NSPoint(x: textX, y: 262),
     font: .systemFont(ofSize: 128, weight: .bold), color: .white)
draw("JianMi", at: NSPoint(x: textX + 350, y: 285),
     font: .systemFont(ofSize: 76, weight: .light),
     color: NSColor(calibratedWhite: 1, alpha: 0.38), kern: 2)

draw("简单记录你的密码，但你的密码将会 100% 安全。",
     at: NSPoint(x: textX + 6, y: 190),
     font: .systemFont(ofSize: 34, weight: .medium),
     color: NSColor(calibratedWhite: 0.82, alpha: 1))

draw("Self-hosted · Zero-knowledge · Native macOS",
     at: NSPoint(x: textX + 6, y: 132),
     font: .monospacedSystemFont(ofSize: 27, weight: .regular),
     color: NSColor(calibratedRed: 0.42, green: 0.58, blue: 1.0, alpha: 1), kern: 1)

// ── 底部特性条 ──
let feats = "⌥⌘N 快速捕获      ⌥⌘P 快速搜索      Argon2id + XChaCha20      浏览器扩展      Rust 同步服务端"
draw(feats, at: NSPoint(x: textX + 6, y: 66),
     font: .systemFont(ofSize: 21, weight: .regular),
     color: NSColor(calibratedWhite: 0.45, alpha: 1))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("渲染失败")
}
let url = URL(fileURLWithPath: outputDir).appendingPathComponent("banner.png")
try! png.write(to: url)
print("已生成 \(url.path)")
