import LastroKit
import SwiftUI

struct HistoricoView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: YearMonth?

    var body: some View {
        let current = store.today.month
        let h = YearHistory(store.ledger, current: current, today: store.today.day)
        let sel = selected ?? current.previous
        let detail = MonthDetail(store.ledger, month: sel, current: current, today: store.today.day)

        Screen(title: "Histórico", subtitle: "\(current.year) · sobra por mês", style: .tab) {
            VStack(spacing: 14) {
                HStack {
                    Text("Acumulado no ano")
                    Spacer()
                    Text(BRL.rounded(h.total)).fontWeight(.bold).monospacedDigit().foregroundStyle(.ink)
                }
                .textStyle(13).foregroundStyle(.inkTertiary)
                .padding(.horizontal, 6)

                LeftoverBars(points: h.points, selected: sel) { m in
                    withAnimation(.smooth(duration: 0.25)) { selected = m }
                }
            }
            .padding(.horizontal, 14).padding(.top, 18).padding(.bottom, 14)
            .panel(radius: 28, fill: 0.66)

            VStack(alignment: .leading, spacing: 14) {
                Text(sel.name + (detail.isForecast ? " · previsto" : ""))
                    .textStyle(18, .bold, tracking: -0.02)
                    .contentTransition(.opacity)
                HStack {
                    figure("Entrou", BRL.rounded(detail.income))
                    figure("Saiu", BRL.rounded(detail.out))
                    figure("Sobrou", BRL.rounded(detail.leftover),
                           color: detail.leftover.isNegative ? .negative : .positive)
                }
                Rectangle().fill(.track).frame(height: 1)
                Text("Maiores categorias").eyebrow().foregroundStyle(.ink.opacity(0.45))
                ForEach(detail.top) { t in
                    HStack(spacing: 12) {
                        CategoryIcon(t.category, size: 34, radius: 11)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(t.category.name)
                                Spacer()
                                Text(BRL.rounded(t.amount)).monospacedDigit()
                            }
                            .textStyle(14, .semibold)
                            ProgressBar(fraction: Double(t.amount.cents) / Double(max(1, detail.top.first?.amount.cents ?? 1)),
                                        color: .category(t.category.hue), height: 4)
                            Text(verbatim: "\(Int((Double(t.amount.cents) / Double(max(1, detail.out.cents)) * 100).rounded()))% do que saiu")
                                .textStyle(11.5).foregroundStyle(.ink.opacity(0.45))
                        }
                    }
                }
            }
            .foregroundStyle(.ink)
            .padding(18)
            .panel(radius: 26)
            .animation(.smooth(duration: 0.25), value: sel)
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func figure(_ label: String, _ value: String, color: Color = .ink) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).textStyle(12).foregroundStyle(.inkTertiary)
            Text(value).textStyle(17, .bold, tracking: -0.02).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Barras de sobra (pra cima) e falta (pra baixo), uma por mês.
struct LeftoverBars: View {
    let points: [YearHistory.Point]
    let selected: YearMonth
    let select: (YearMonth) -> Void

    var body: some View {
        let mx = Double(max(1, points.map(\.leftover.magnitude.cents).max() ?? 1))
        HStack(spacing: 4) {
            ForEach(points) { p in
                let isSel = p.month == selected
                let v = Double(p.leftover.cents)
                Button { select(p.month) } label: {
                    VStack(spacing: 0) {
                        ZStack(alignment: .bottom) {
                            Color.clear
                            if v > 0 {
                                UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 8)
                                    .fill(color(p, isSel))
                                    .frame(height: v / mx * 104)
                            }
                        }
                        .frame(height: 108)
                        Rectangle().fill(.ink.opacity(0.14)).frame(height: 1)
                        ZStack(alignment: .top) {
                            Color.clear
                            if v < 0 {
                                UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 3)
                                    .fill(color(p, isSel))
                                    .frame(height: min(44, -v / mx * 104))
                            }
                        }
                        .frame(height: 46)
                        Text(p.month.shortName).textStyle(10.5, .semibold, tracking: 0.03)
                            .foregroundStyle(isSel ? Color.ink : Color.ink.opacity(0.4))
                    }
                    .padding(.horizontal, 2)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.month.name), \(BRL.rounded(p.leftover))")
            }
        }
    }

    private func color(_ p: YearHistory.Point, _ isSel: Bool) -> Color {
        if p.leftover.isNegative { return isSel ? .negative : Color(Palette.red).opacity(0.32) }
        if p.isForecast { return isSel ? .accent : Color(Palette.accent).opacity(0.35) }
        return isSel ? .ink : .ink.opacity(0.16)
    }
}
