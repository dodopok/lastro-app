import LastroKit
import SwiftUI

// Tokens do design (Lastro.dc.html). Cores em OKLCH convertidas para Display P3.

extension Color {
    init(_ c: OKLCH) {
        let p = c.displayP3
        self.init(.displayP3, red: p.r, green: p.g, blue: p.b, opacity: c.alpha)
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    static func category(_ hue: Double) -> Color { Color(Palette.category(hue)) }
    static func categoryTint(_ hue: Double, _ alpha: Double = 0.16) -> Color { Color(Palette.categoryTint(hue, alpha: alpha)) }
}

extension ShapeStyle where Self == Color {
    /// #15161B: texto e elementos "tinta".
    static var ink: Color { Color(hex: 0x15161B) }
    /// #F3F3F1: fundo do app.
    static var canvas: Color { Color(hex: 0xF3F3F1) }
    /// Sombra azulada rgba(22,24,40).
    static var shade: Color { Color(hex: 0x161828) }

    static var accent: Color { Color(Palette.accent) }
    static var positive: Color { Color(Palette.green) }
    static var negative: Color { Color(Palette.red) }
    static var warning: Color { Color(Palette.amber) }

    /// rgba(21,22,27,.55) e família: hierarquia de texto por opacidade da tinta.
    static var inkSecondary: Color { .ink.opacity(0.55) }
    static var inkTertiary: Color { .ink.opacity(0.5) }
    static var inkQuaternary: Color { .ink.opacity(0.4) }
    static var hairline: Color { .ink.opacity(0.06) }
    static var track: Color { .ink.opacity(0.07) }
}

/// Gradiente do botão principal: oklch(.62 .2 262) → oklch(.51 .22 264).
extension LinearGradient {
    static var accentButton: LinearGradient {
        LinearGradient(colors: [Color(OKLCH(0.62, 0.20, 262)), Color(OKLCH(0.51, 0.22, 264))],
                       startPoint: .top, endPoint: .bottom)
    }
    static var accentFab: LinearGradient {
        LinearGradient(colors: [Color(Palette.accentTop), Color(Palette.accentBottom)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Tipografia

/// Tamanhos e tracking do design. Tracking vem em em, como no CSS (-.035em).
extension View {
    nonisolated func textStyle(_ size: CGFloat, _ weight: Font.Weight = .regular, tracking: CGFloat = 0) -> some View {
        font(.system(size: size, weight: weight)).tracking(size * tracking)
    }

    /// Título grande da tela: 34 bold, -.035em.
    nonisolated func largeTitle() -> some View { textStyle(34, .bold, tracking: -0.035) }
    /// Título de tela empilhada: 30 bold, -.035em.
    nonisolated func pushedTitle() -> some View { textStyle(30, .bold, tracking: -0.035) }
    /// Título de seção: 20 bold, -.025em.
    nonisolated func sectionTitle() -> some View { textStyle(20, .bold, tracking: -0.025) }
    /// Rótulo em caixa alta: 12 bold, .06em.
    nonisolated func eyebrow() -> some View { textStyle(12, .bold, tracking: 0.06).textCase(.uppercase) }
}
