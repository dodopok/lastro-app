import LastroKit
import SwiftUI

struct CategoriaView: View {
    @Environment(AppStore.self) private var store
    let categoryId: UUID

    var body: some View {
        let month = store.today.month
        let m = CurrentMonth(store.ledger, month: month, today: store.today.day)
        if let status = m.categories.first(where: { $0.category.id == categoryId }) {
            content(status, month: month, today: store.today.day)
        } else {
            Screen(title: "Categoria") { EmptyView() }
        }
    }

    private func content(_ s: CategoryStatus, month: YearMonth, today: Int) -> some View {
        let c = s.category
        let entries = store.ledger.entries(in: month).filter { $0.categoryId == c.id }.sorted { ($0.day, $0.amountCents) > ($1.day, $1.amountCents) }
        let ring = s.isOver ? Color.negative : Color.category(c.hue)

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    CategoryIcon(c, size: 44, radius: 14)
                    Text(c.name).textStyle(30, .bold, tracking: -0.035).foregroundStyle(.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 4)

                HStack(spacing: 20) {
                    ZStack {
                        Circle().stroke(.track, lineWidth: 12)
                        Circle().trim(from: 0, to: s.fraction)
                            .stroke(ring, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(verbatim: "\(s.percent)%").textStyle(28, .bold, tracking: -0.04).monospacedDigit()
                            Text("usado").textStyle(11).foregroundStyle(.inkTertiary)
                        }
                        .foregroundStyle(.ink)
                    }
                    .frame(width: 128, height: 128)
                    .padding(6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(BRL.format(s.spent)).textStyle(24, .bold, tracking: -0.03).monospacedDigit().foregroundStyle(.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("de " + BRL.format(s.budget)).textStyle(13).monospacedDigit().foregroundStyle(.inkTertiary)
                        Text(s.isOver ? "passou " + BRL.format(-s.left) : "sobra " + BRL.format(s.left))
                            .textStyle(14, .semibold)
                            .foregroundStyle(s.isOver ? Color.negative : Color.positive)
                            .padding(.top, 6)
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
                .hero(radius: 30)

                Callout(symbol: "sparkle", eyebrow: "Padrão",
                        text: Insights.category(c, entries: entries, month: month, today: today))

                HStack(spacing: 10) {
                    stat("Ticket médio", entries.isEmpty ? BRL.format(.zero) : BRL.format(s.spent.divided(by: entries.count)))
                    stat("Lançamentos", "\(entries.count)")
                }

                SectionHeader(title: month.name)
                if entries.isEmpty {
                    Text("Nenhum lançamento ainda.").textStyle(14).foregroundStyle(.inkTertiary).padding(.horizontal, 4)
                } else {
                    PanelList(data: entries, radius: 22) { e in
                        CheckRow(entry: e, meta: "\(Ledger.dayLabel(e.day, today: today)) · \(store.ledger.paidWith(e))") {
                            store.toggleConfirmed(e)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).textStyle(12.5).foregroundStyle(.inkTertiary)
            Text(value).textStyle(20, .bold, tracking: -0.02).monospacedDigit().foregroundStyle(.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .panel(radius: 20)
    }
}

/// Linha com check de confirmado (detalhe de categoria).
struct CheckRow: View {
    let entry: Entry
    let meta: String
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(entry.confirmed ? Color.positive : Color.ink.opacity(0.22), lineWidth: 1.6)
                    if entry.confirmed {
                        Circle().fill(Color.positive)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    }
                }
                .frame(width: 20, height: 20)
                .animation(.snappy(duration: 0.2), value: entry.confirmed)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.description).textStyle(15, .semibold).foregroundStyle(.ink)
                    Text(meta).textStyle(12.5).foregroundStyle(.inkTertiary)
                }
                Spacer(minLength: 0)
                Text(BRL.format(entry.amountCents)).textStyle(15, .semibold).monospacedDigit().foregroundStyle(.ink)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(RowPressStyle())
        .sensoryFeedback(.success, trigger: entry.confirmed) { _, new in new }
    }
}
