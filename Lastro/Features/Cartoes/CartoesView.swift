import LastroKit
import SwiftUI

struct CartoesView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: UUID?

    var body: some View {
        let cards = store.ledger.activeCards
        let m = CurrentMonth(store.ledger, month: store.today.month, today: store.today.day)
        let current = cards.first { $0.id == selected } ?? cards.first

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Cartões").pushedTitle().foregroundStyle(.ink)
                    Text("forma de pagamento, não categoria").textStyle(13.5).foregroundStyle(.inkTertiary)
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(cards) { c in
                            CreditCardView(card: c, statement: m.statement(card: c.id), selected: c.id == current?.id)
                                .onTapGesture { withAnimation(.smooth(duration: 0.22)) { selected = c.id } }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .sensoryFeedback(.selection, trigger: selected)

                if let c = current {
                    details(c, month: m)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(_ c: Card, month m: CurrentMonth) -> some View {
        let statement = m.statement(card: c.id)
        let usage = c.limitCents.cents > 0 ? Double(statement.cents) / Double(c.limitCents.cents) : 0
        let purchases = m.entries.filter { $0.cardId == c.id }.sorted { $0.day > $1.day }
        let carried = store.ledger.carryover(card: c.id, in: m.month)
        let today = m.today

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.name).textStyle(17, .bold)
                    Spacer()
                    Text(verbatim: "\(Int((usage * 100).rounded()))% do limite").textStyle(13, .semibold).foregroundStyle(.inkSecondary)
                }
                ProgressBar(fraction: usage, color: Color(OKLCH(0.54, 0.15, c.hue)), height: 8)
                HStack {
                    fact("Fecha", "dia \(c.closingDay)")
                    fact("Vence", "dia \(c.dueDay)")
                    fact("Livre", BRL.rounded(c.limitCents - statement))
                }
            }
            .foregroundStyle(.ink)
            .padding(18)
            .panel(radius: 26, fill: 0.66)

            Callout(symbol: "exclamationmark.circle", text: Insights.cards(store.ledger.activeCards),
                    tint: Color(OKLCHColor.amberSoft), iconColor: Color(OKLCHColor.amberText))

            SectionHeader(title: "Compras na fatura")
            VStack(spacing: 0) {
                if carried.cents > 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Parcelas e meses anteriores").textStyle(15, .semibold)
                            Text("já estavam na fatura").textStyle(12.5).foregroundStyle(.inkTertiary)
                        }
                        Spacer()
                        Text(BRL.format(carried)).textStyle(15, .semibold).monospacedDigit()
                    }
                    .foregroundStyle(.ink)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                ForEach(Array(purchases.enumerated()), id: \.element.id) { i, e in
                    if i > 0 || carried.cents > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        if let cat = store.ledger.category(e.categoryId) { CategoryIcon(cat, size: 34, radius: 11) }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(e.description).textStyle(15, .semibold)
                            Text("\(Ledger.dayLabel(e.day, today: today)) · \(store.ledger.category(e.categoryId)?.name ?? "")")
                                .textStyle(12.5).foregroundStyle(.inkTertiary)
                        }
                        Spacer()
                        Text(BRL.format(e.amountCents)).textStyle(15, .semibold).monospacedDigit()
                    }
                    .foregroundStyle(.ink)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                }
                if purchases.isEmpty && carried.cents == 0 {
                    Text("Nenhuma compra neste cartão ainda.").textStyle(14).foregroundStyle(.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
            .panel()
        }
        .animation(.smooth(duration: 0.3), value: c.id)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).textStyle(11.5).foregroundStyle(.inkTertiary)
            Text(value).textStyle(15, .semibold).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// O cartão físico: gradiente do matiz do cartão com brilho diagonal.
struct CreditCardView: View {
    let card: Card
    let statement: Money
    let selected: Bool

    var body: some View {
        let g = Palette.card(card.hue)
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Text(card.name).textStyle(16, .bold, tracking: -0.01)
                Spacer()
                Text(card.subtitle ?? "").textStyle(11.5).opacity(0.8)
            }
            Spacer()
            Text("fatura aberta").textStyle(11.5).opacity(0.8)
            Text(BRL.format(statement)).textStyle(24, .bold, tracking: -0.03).monospacedDigit()
            Text("fecha \(card.closingDay) · vence \(card.dueDay)").textStyle(11.5).opacity(0.85).padding(.top, 2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(width: 236, height: 148)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(g.top), Color(g.bottom)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.28), location: 0), .init(color: .white.opacity(0), location: 0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white, lineWidth: 3)
                RoundedRectangle(cornerRadius: 25, style: .continuous).strokeBorder(Color.ink, lineWidth: 2).padding(-3)
            }
        }
        .shadow(color: .black.opacity(selected ? 0.4 : 0.3), radius: selected ? 15 : 12, y: selected ? 18 : 12)
        .opacity(selected ? 1 : 0.78)
        .scaleEffect(selected ? 1 : 0.97)
        .contentShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}
