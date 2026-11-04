import SwiftUI
import UIKit

enum Theme {
    static let text = dyn(0x1F2129, 0xEDEEF2)
    static let text2 = dyn(0x606370, 0xB3B5BF)
    static let gray = dyn(0x979AA8, 0x868996)
    static let line = dyn(0xEBECEF, 0x2C2D33)
    static let bg = dyn(0xF5F6F7, 0x0B0B0D)
    static let card = dyn(0xFFFFFF, 0x1A1B1F)     // page / card background
    static let price = Color(hex: 0xFF4F14)      // orange-red price
    static let yellow = Color(hex: 0xFFE100)     // brand accent
    static let onYellow = Color(hex: 0x1F2129)   // text on the yellow accent (both modes)
    static let chipBg = dyn(0xF2F3F5, 0x2A2B31)
    static let selBg = dyn(0xFFF9D6, 0x3A3212)
    static let selText = dyn(0xB87A00, 0xFFC933)
    static let faint = dyn(0xC0C2CA, 0x55575F)
    static let green = Color(hex: 0x1BA35C)

    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
    /// Parses "rgb(1,2,3)" / "rgba(1,2,3,0.1)" / "#RRGGBB" as returned by the API.
    init?(css: String) {
        let s = css.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#"), let v = UInt32(s.dropFirst(), radix: 16), s.count == 7 { self.init(hex: v); return }
        guard let o = s.firstIndex(of: "("), let c = s.firstIndex(of: ")") else { return nil }
        let parts = s[s.index(after: o)..<c].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        self.init(.sRGB, red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, opacity: parts.count > 3 ? parts[3] : 1)
    }
}

// MARK: - Image loading with memory + disk cache

struct RemoteImage: View {
    let url: String
    var mode: ContentMode = .fill
    /// Longest side in points the image is shown at; decoded at that × screen scale.
    var maxPoints: CGFloat = 200
    @State private var image: UIImage?
    var px: Int { Int(maxPoints * UIScreen.main.scale) }
    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: mode)
            } else {
                Theme.chipBg.overlay(Image(systemName: "car.side").font(.system(size: 18)).foregroundColor(Theme.faint))
            }
        }
        .task(id: url) {
            if let c = ImageLoader.shared.cached(url, px: px) { image = c; return }
            image = nil
            image = await ImageLoader.shared.load(url, px: px)
        }
    }
}

struct TagView: View {
    let tag: CarTag
    var body: some View {
        Text(tag.text)
            .font(.system(size: 10))
            .foregroundColor(Color(css: tag.textColor) ?? Theme.text2)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(Color(css: tag.bgColor) ?? Theme.chipBg)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

struct Shimmer: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content.opacity(on ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// Shown when the API marks a listing is_self_trade (懂车帝官方直营).
struct SelfBadge: View {
    var text = "直营"
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.onYellow)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(Theme.yellow)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
