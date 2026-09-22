import LastroKit
import SwiftUI

extension View {
    /// Fundo do design por baixo de cada tela. Precisa estar dentro da
    /// NavigationStack: ela pinta um fundo opaco que esconderia o Backdrop.
    func screenBackground() -> some View {
        background { Backdrop() }
            .overlay(alignment: .top) { TopFade() }
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// Fade sob a status bar (96px no design) para o conteúdo sumir ao rolar.
struct TopFade: View {
    var body: some View {
        LinearGradient(stops: [.init(color: .canvas.opacity(0.85), location: 0),
                               .init(color: .canvas.opacity(0.6), location: 0.45),
                               .init(color: .canvas.opacity(0), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 34)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}

/// Tela padrão: título grande (aba) ou título de tela empilhada, e o conteúdo rolando.
struct Screen<Content: View>: View {
    enum Style { case tab, pushed }

    let title: String
    var subtitle: String?
    var style: Style = .pushed
    var spacing: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                header
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, style == .tab ? 8 : 0)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch style {
            case .tab:
                if let subtitle { Text(subtitle).textStyle(13, .medium).foregroundStyle(.inkTertiary) }
                Text(title).largeTitle().foregroundStyle(.ink)
            case .pushed:
                Text(title).pushedTitle().foregroundStyle(.ink)
                if let subtitle { Text(subtitle).textStyle(13.5).monospacedDigit().foregroundStyle(.inkTertiary) }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, style == .tab ? 8 : 0)
    }
}

/// Título de seção dentro de uma tela ("Contas", "Compras na fatura"…).
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).sectionTitle().foregroundStyle(.ink)
            Spacer()
            if let trailing { Text(trailing).textStyle(12.5).monospacedDigit().foregroundStyle(.ink.opacity(0.45)) }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

/// Rótulo pequeno acima de um grupo ("Valor sempre igual · renova igual").
struct GroupLabel: View {
    let text: String
    var body: some View {
        Text(text).textStyle(13, .semibold).foregroundStyle(.inkTertiary).padding(.horizontal, 6).padding(.top, 6)
    }
}

/// Lista dentro de um painel, com separadores entre as linhas.
struct PanelList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    var radius: CGFloat = 24
    @ViewBuilder let row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { i, item in
                if i > 0 { RowDivider() }
                row(item)
            }
        }
        .panel(radius: radius)
    }
}

/// Caixa de destaque com ícone ("Padrão", aviso dos cartões, nota do Face ID).
struct Callout: View {
    let symbol: String
    var eyebrow: String?
    let text: String
    var tint: Color = Color(OKLCHColor.accentSoft)
    var iconColor: Color = .accent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(iconColor)
                .frame(width: 20).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow { Text(eyebrow).eyebrow().foregroundStyle(iconColor) }
                Text(text).textStyle(eyebrow == nil ? 14 : 15).foregroundStyle(.ink).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .tinted(tint)
    }
}

enum OKLCHColor {
    static let accentSoft = OKLCH(0.95, 0.04, 262, alpha: 0.85)
    static let amberSoft = OKLCH(0.96, 0.06, 85, alpha: 0.85)
    static let amberText = OKLCH(0.55, 0.14, 62)
}

/// Stepper −/+ em cápsula (planejar, vencimento).
struct PillStepper: View {
    let value: String
    var minWidth: CGFloat = 66
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            stepButton("minus", action: minus)
            Text(value).textStyle(13.5, .semibold).monospacedDigit().foregroundStyle(.ink)
                .frame(minWidth: minWidth)
                .contentTransition(.numericText())
            stepButton("plus", action: plus)
        }
        .padding(3)
        .background(.ink.opacity(0.05), in: .capsule)
        .sensoryFeedback(.selection, trigger: value)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(.ink)
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(StepStyle())
    }
}

private struct StepStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white : .clear, in: .circle)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Número grande de um card herói secundário (44pt, sem centavos atenuados).
struct BigAmount: View {
    let text: String
    var size: CGFloat = 44
    var color: Color = .ink

    var body: some View {
        Text(text).textStyle(size, .bold, tracking: -0.045).monospacedDigit().foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.6)
            .contentTransition(.numericText())
    }
}
