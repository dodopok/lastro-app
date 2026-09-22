import LastroKit
import SwiftUI

// "Vidro apenas em camadas que flutuam": tab bar, botões, card herói, sheets.
// Os cards de conteúdo são um fosco claro (material + branco .6), não Liquid Glass.

/// Card de conteúdo: blur + branco .6 + borda branca + sombra suave.
struct PanelSurface: ViewModifier {
    var radius: CGFloat = 22
    var fill: Double = 0.6

    nonisolated init(radius: CGFloat = 22, fill: Double = 0.6) {
        self.radius = radius
        self.fill = fill
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(.ultraThinMaterial)
                shape.fill(.white.opacity(fill))
            }
            .overlay(alignment: .top) {
                // inset 0 1px 0 #fff
                shape.strokeBorder(
                    LinearGradient(colors: [.white, .white.opacity(0.9)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            .clipShape(shape)
            .shadow(color: .shade.opacity(0.10), radius: 14, y: 12)
    }
}

/// Card herói: gradiente branco .88 → .5 com Liquid Glass por baixo.
struct HeroSurface: ViewModifier {
    var radius: CGFloat = 32

    nonisolated init(radius: CGFloat = 32) { self.radius = radius }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(LinearGradient(colors: [.white.opacity(0.88), .white.opacity(0.5)],
                                          startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1)))
            }
            .glassEffect(.regular, in: shape)
            .overlay { shape.strokeBorder(.white.opacity(0.95), lineWidth: 1) }
            .shadow(color: Color(red: 40 / 255, green: 50 / 255, blue: 120 / 255).opacity(0.22), radius: 22, y: 24)
    }
}

/// Faixa de destaque com tom (Miudezas âmbar, Padrão azul).
struct TintedSurface: ViewModifier {
    let tint: Color
    var radius: CGFloat = 24

    nonisolated init(tint: Color, radius: CGFloat = 24) {
        self.tint = tint
        self.radius = radius
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(.ultraThinMaterial)
                shape.fill(LinearGradient(colors: [tint, .white.opacity(0.5)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay { shape.strokeBorder(.white.opacity(0.9), lineWidth: 1) }
            .clipShape(shape)
    }
}

extension View {
    nonisolated func panel(radius: CGFloat = 22, fill: Double = 0.6) -> some View { modifier(PanelSurface(radius: radius, fill: fill)) }
    nonisolated func hero(radius: CGFloat = 32) -> some View { modifier(HeroSurface(radius: radius)) }
    nonisolated func tinted(_ tint: Color, radius: CGFloat = 24) -> some View { modifier(TintedSurface(tint: tint, radius: radius)) }

    /// Botão redondo de vidro (40–44pt) do cabeçalho.
    nonisolated func glassCircle(_ size: CGFloat = 40) -> some View {
        frame(width: size, height: size)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }

    nonisolated func glassPill(height: CGFloat = 40) -> some View {
        frame(height: height)
            .padding(.horizontal, 14)
            .contentShape(.capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// Fundo do app: três manchas de cor desfocadas sobre o canvas.
struct Backdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.canvas
                Circle().fill(Color(OKLCH(0.84, 0.10, 262))).frame(width: 440, height: 440)
                    .blur(radius: 80).opacity(0.5)
                    .position(x: -170 + 220, y: -150 + 220)
                Circle().fill(Color(OKLCH(0.90, 0.09, 165))).frame(width: 380, height: 380)
                    .blur(radius: 80).opacity(0.6)
                    .position(x: geo.size.width + 190 - 190, y: 320 + 190)
                Circle().fill(Color(OKLCH(0.90, 0.08, 55))).frame(width: 400, height: 400)
                    .blur(radius: 80).opacity(0.6)
                    .position(x: -160 + 200, y: geo.size.height + 140 - 200)
            }
        }
        .ignoresSafeArea()
    }
}

/// Separador entre linhas de uma lista dentro de um panel.
struct RowDivider: View {
    var body: some View { Rectangle().fill(.hairline).frame(height: 1) }
}
