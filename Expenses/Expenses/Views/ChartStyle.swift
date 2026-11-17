import SwiftUI
import AppKit

/// Fixed colour per category (light, dark), so a category keeps its colour whatever is filtered.
enum ChartStyle {
    private static let slots: [(String, String, String)] = [
        ("Food", "#2a78d6", "#3987e5"), ("Transport", "#eb6834", "#d95926"),
        ("Utilities", "#1baf7a", "#199e70"), ("Office", "#eda100", "#c98500"),
        ("Software", "#e87ba4", "#d55181"), ("Travel", "#008300", "#008300"),
        ("Health", "#4a3aa7", "#9085e9"), ("Other", "#e34948", "#e66767"),
    ]

    static let categoryOrder: [String] = slots.map { $0.0 }
    static let categoryColors: [Color] = slots.map { dynamic(light: $0.1, dark: $0.2) }
    static let accent = dynamic(light: "#2a78d6", dark: "#3987e5")

    static func color(for category: String) -> Color {
        guard let index = categoryOrder.firstIndex(of: category) else { return categoryColors.last! }
        return categoryColors[index]
    }

    private static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
