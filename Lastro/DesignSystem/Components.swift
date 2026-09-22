import LastroKit
import SwiftUI

/// Ícone de categoria: quadrado arredondado com o tom da categoria a 16%.
struct CategoryIcon: View {
    let symbol: String
    let hue: Double
    var size: CGFloat = 36
    var radius: CGFloat = 12

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(Color.category(hue))
            .frame(width: size, height: size)
            .background(Color.categoryTint(hue), in: .rect(cornerRadius: radius, style: .continuous))
    }
}

extension CategoryIcon {
    init(_ c: BudgetCategory, size: CGFloat = 36, radius: CGFloat = 12) {
        self.init(symbol: c.symbol, hue: c.hue, size: size, radius: radius)
    }
}

/// Número herói: "R$" menor, inteiro grande, centavos a 38%.
struct HeroAmount: View {
    let value: Money
    var integerSize: CGFloat = 58
    var color: Color? = nil

    var body: some View {
        let p = BRL.heroParts(value)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(p.sign + "R$")
                .textStyle(integerSize * 0.38, .semibold, tracking: -0.02)
                .padding(.trailing, 6)
            Text(p.integer)
                .textStyle(integerSize, .bold, tracking: -0.05)
            Text(p.cents)
                .textStyle(integerSize * 0.45, .semibold, tracking: -0.03)
                .opacity(0.38)
        }
        .monospacedDigit()
        .foregroundStyle(color ?? (value.isNegative ? .negative : .ink))
        .contentTransition(.numericText(value: value.reais))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Barra fina de progresso.
struct ProgressBar: View {
    let fraction: Double
    var color: Color = .ink
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.track)
                Capsule().fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.22), value: fraction)
    }
}

/// Etiqueta pequena ("Aprovar", "estimado", "Piloto").
struct Tag: View {
    let text: String
    var color: Color = .inkSecondary
    var background: Color = .ink.opacity(0.06)

    var body: some View {
        Text(text)
            .textStyle(10.5, .bold)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background, in: .capsule)
    }
}

/// Chip de seleção (categoria no lançamento, filtros).
struct SelectChip<Leading: View>: View {
    let title: String
    let selected: Bool
    var selectedFill: Color = .ink
    var selectedStroke: Color = .ink
    var selectedText: Color = .white
    var height: CGFloat = 36
    @ViewBuilder var leading: () -> Leading
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                leading()
                Text(title).textStyle(13, .semibold).lineLimit(1)
            }
            .padding(.leading, Leading.self == EmptyView.self ? 12 : 6)
            .padding(.trailing, 12)
            .frame(height: height)
            .foregroundStyle(selected ? selectedText : .ink)
            .background(selected ? selectedFill : .white.opacity(0.6), in: .capsule)
            .overlay { Capsule().strokeBorder(selected ? selectedStroke : .ink.opacity(0.08), lineWidth: 1) }
            .contentShape(.capsule)
            .animation(.smooth(duration: 0.22), value: selected)
        }
        .buttonStyle(.plain)
    }
}

extension SelectChip where Leading == EmptyView {
    init(title: String, selected: Bool, height: CGFloat = 32, action: @escaping () -> Void) {
        self.init(title: title, selected: selected, height: height, leading: { EmptyView() }, action: action)
    }
}

/// Botão principal azul (Salvar, Salvar em…).
struct PrimaryButton: View {
    let title: String
    var enabled = true
    var height: CGFloat = 54
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(16.5, .semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(LinearGradient.accentButton, in: .capsule)
                .overlay(alignment: .top) {
                    Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1).mask(alignment: .top) {
                        Rectangle().frame(height: 2)
                    }
                }
                .shadow(color: Color(Palette.accentBottom).opacity(0.45), radius: 12, y: 12)
        }
        .buttonStyle(PressScale())
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .animation(.smooth(duration: 0.22), value: enabled)
    }
}

/// `style-active="transform:scale(.98)"`
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Seta de "ir para" nas linhas.
struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.ink.opacity(0.3))
    }
}

/// Linha de lista: realce leve ao tocar, área inteira tocável.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .background(configuration.isPressed ? Color.ink.opacity(0.04) : .clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
