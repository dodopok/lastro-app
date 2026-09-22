import LastroKit
import SwiftUI

struct PlanejarView: View {
    @Environment(AppStore.self) private var store
    let month: YearMonth
    @State private var showPresets = false

    private static let step = Money(cents: 5_000)
    private static let presets: [(String, Money)] = [
        ("IPVA", Money(cents: 148_000)), ("Presente", Money(cents: 25_000)),
        ("Viagem", Money(cents: 120_000)), ("Revisão do carro", Money(cents: 65_000)),
    ]

    var body: some View {
        let p = PlannedMonth(store.ledger, month: month)
        let previous = month.previous

        Screen(title: "Planejar \(month.name.lowercased())", subtitle: "fixas já copiadas · ajuste o resto") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sobra projetada").textStyle(14, .semibold).foregroundStyle(.ink.opacity(0.6))
                BigAmount(text: BRL.format(p.leftover), color: p.leftover.isNegative ? .negative : .ink)
                Text("dá pra guardar \(Text(BRL.format(p.savable)).fontWeight(.bold).foregroundStyle(Color.ink)) · planejado \(BRL.rounded(p.total))")
                    .textStyle(13.5).monospacedDigit().foregroundStyle(.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .hero(radius: 30)

            VStack(spacing: 0) {
                ForEach(Array(store.ledger.activeCategories.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { RowDivider() }
                    let v = p.budget(c.id)
                    let d = v - store.ledger.budget(for: c.id, in: previous)
                    HStack(spacing: 10) {
                        CategoryIcon(c, size: 34, radius: 11)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.name).textStyle(14.5, .semibold).foregroundStyle(.ink).lineLimit(1)
                            Text(d.cents == 0 ? c.budgetOrigin : "\(d.isNegative ? BRL.minus : "+")\(BRL.rounded(d.magnitude)) vs. \(previous.name.lowercased())")
                                .textStyle(12)
                                .foregroundStyle(d.cents == 0 ? Color.ink.opacity(0.45) : d.isNegative ? Color.positive : Color.negative)
                        }
                        Spacer(minLength: 0)
                        PillStepper(value: BRL.rounded(v),
                                    minus: { store.stepBudget(month, c.id, by: -Self.step) },
                                    plus: { store.stepBudget(month, c.id, by: Self.step) })
                    }
                    .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
                }
                ForEach(p.extras) { e in
                    RowDivider()
                    HStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(.ink.opacity(0.06), in: .rect(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(e.name).textStyle(14.5, .semibold)
                            Text("só deste mês").textStyle(12).foregroundStyle(.ink.opacity(0.45))
                        }
                        Spacer(minLength: 0)
                        PillStepper(value: BRL.rounded(e.amountCents),
                                    minus: { store.stepExtra(e.id, by: -Self.step) },
                                    plus: { store.stepExtra(e.id, by: Self.step) })
                    }
                    .foregroundStyle(.ink)
                    .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .panel(radius: 24)
            .animation(.smooth(duration: 0.25), value: p.extras.map(\.id))

            Button { withAnimation(.smooth(duration: 0.22)) { showPresets.toggle() } } label: {
                Label("Item só deste mês", systemImage: "plus")
                    .textStyle(15, .semibold)
                    .foregroundStyle(Color(OKLCH(0.5, 0.2, 262)))
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .overlay { Capsule().strokeBorder(Color(Palette.accent).opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])) }
                    .contentShape(.capsule)
            }
            .buttonStyle(PressScale())

            if showPresets {
                FlowLayout(spacing: 8) {
                    ForEach(Self.presets, id: \.0) { name, value in
                        Button {
                            store.addExtra(month, name: name, amount: value)
                            withAnimation(.smooth(duration: 0.22)) { showPresets = false }
                        } label: {
                            Text("\(name) · \(BRL.rounded(value))").textStyle(13.5, .semibold).foregroundStyle(.ink)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background(.white.opacity(0.7), in: .capsule)
                                .overlay { Capsule().strokeBorder(.ink.opacity(0.08), lineWidth: 1) }
                                .contentShape(.capsule)
                        }
                        .buttonStyle(PressScale())
                    }
                }
                .transition(.opacity)
            }

            Text("Sem limite de linhas. Adicionar item é só adicionar.")
                .textStyle(12.5).foregroundStyle(.ink.opacity(0.45))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
    }
}
