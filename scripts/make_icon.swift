// 生成简密 App 图标：蓝色渐变圆角方 + 白色钥匙
// 用法: swift scripts/make_icon.swift <输出目录>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS 图标标准留白（约 10%）+ 圆角方形
let inset: CGFloat = size * 0.1
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = rect.width * 0.225
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// 渐变背景
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.35, green: 0.55, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.85, alpha: 1),
])!
gradient.draw(in: path, angle: -60)

// 白色钥匙符号
let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let symbolSize = NSSize(width: size * 0.42, height: size * 0.42 * (symbol.size.height / symbol.size.width))
    let origin = NSPoint(x: (size - symbolSize.width) / 2, y: (size - symbolSize.height) / 2)

    // 旋转 -25° 绘制
    NSGraphicsContext.current?.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: size / 2, yBy: size / 2)
    transform.rotate(byDegrees: -25)
    transform.translateX(by: -size / 2, yBy: -size / 2)
    transform.concat()
    symbol.draw(in: NSRect(origin: origin, size: symbolSize))
    NSGraphicsContext.current?.restoreGraphicsState()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("渲染失败")
}
let url = URL(fileURLWithPath: outputDir).appendingPathComponent("icon_1024.png")
try! png.write(to: url)
print("已生成 \(url.path)")
