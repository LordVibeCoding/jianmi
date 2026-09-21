import MarkdownUI
import SwiftUI

// ── Markdown 主题 ──────────────────────────────────────
extension MarkdownUI.Theme {
    /// 简密笔记主题：gitHub 的排版（标题分隔线/代码块/引用样式），
    /// 但去掉每块文本的背景色 —— 直接融入窗口背景，备忘录风格。
    static let jianmi = Theme.gitHub.text {
        FontSize(15)
        ForegroundColor(.primary)
    }
}

/// 彩色渐变圆角分类徽章（按分类 ID 解析图标与配色）。
struct TypeBadge: View {
    let typeID: String
    var size: CGFloat = 30

    var body: some View {
        let category = CategoryStore.shared.category(for: typeID)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(
                colors: [category.color.opacity(0.75), category.color],
                startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: category.icon)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: category.color.opacity(0.35), radius: 2, y: 1)
    }
}

/// App 图标徽章（用于面板头部/关于页）。
struct AppBadge: View {
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.32, green: 0.5, blue: 1.0),
                         Color(red: 0.15, green: 0.25, blue: 0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "key.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-25))
            }
            .shadow(color: .blue.opacity(0.35), radius: 2, y: 1)
    }
}

/// 详情页卡片容器。
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(.background.opacity(0.5))
            .background(.quaternary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1))
    }
}

/// 键帽样式的快捷键提示。
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.secondary)
    }
}

/// 面板内的成功提示浮层。
struct SuccessToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
        .shadow(radius: 8, y: 2)
    }
}
