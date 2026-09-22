import LastroKit
import SwiftUI

struct GastosView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""

    var body: some View {
        @Bindable var store = store
        let month = store.today.month
        let today = store.today.day
        let all = store.ledger.entries(in: month)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = all.filter { e in
            let byFilter = switch store.spendingFilter {
            case .todos: true
            case .fixos: e.kind != .variavel
            case .variaveis: e.kind == .variavel
            case .pendentes: !e.confirmed
            }
            let name = store.ledger.category(e.categoryId)?.name.lowercased() ?? ""
            return byFilter && (q.isEmpty || e.description.lowercased().contains(q) || name.contains(q))
        }
        let days = Set(list.map(\.day)).sorted(by: >)

        Screen(title: "Gastos", subtitle: month.name, style: .tab, spacing: 12) {
            searchField
            FilterBar(selection: $store.spendingFilter)
            HStack {
                Text("\(list.count) lançamentos")
                Spacer()
                Text(BRL.format(list.sum(\.amountCents))).fontWeight(.semibold).foregroundStyle(.ink)
            }
            .textStyle(13).monospacedDigit().foregroundStyle(.inkTertiary)
            .padding(.horizontal, 4).padding(.vertical, 2)

            if list.isEmpty {
                Text("Nada por aqui com esse filtro.")
                    .textStyle(14).foregroundStyle(.inkTertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }

            ForEach(days, id: \.self) { d in
                let items = list.filter { $0.day == d }.sorted { $0.amountCents > $1.amountCents }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dayTitle(d, today: today, month: month))
                        Spacer()
                        Text(BRL.format(items.sum(\.amountCents))).monospacedDigit()
                    }
                    .textStyle(13, .semibold).foregroundStyle(.inkTertiary)
                    .padding(.horizontal, 6).padding(.top, 4)

                    PanelList(data: items, radius: 22) { e in
                        EntryRow(entry: e, meta: "\(store.ledger.category(e.categoryId)?.name ?? "") · \(store.ledger.paidWith(e))") {
                            store.toggleConfirmed(e)
                        }
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: store.spendingFilter)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(.ink.opacity(0.45))
            TextField("Buscar iFood, Uber, luz…", text: $query)
                .textStyle(15)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.ink.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
    }

    private func dayTitle(_ d: Int, today: Int, month: YearMonth) -> String {
        d == today ? "Hoje" : d == today - 1 ? "Ontem"
            : d > today ? "\(d) de \(month.name.lowercased()) · previsto" : "\(d) de \(month.name.lowercased())"
    }
}

/// Filtros em cápsula (Todos, Fixos, Variáveis, Não confirmados).
struct FilterBar: View {
    @Binding var selection: SpendingFilter
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SpendingFilter.allCases, id: \.self) { f in
                Button { withAnimation(.smooth(duration: 0.22)) { selection = f } } label: {
                    Text(f.label).textStyle(13, .semibold).lineLimit(1)
                        .foregroundStyle(selection == f ? Color.white : Color.ink.opacity(0.62))
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background {
                            if selection == f { Capsule().fill(Color.ink).matchedGeometryEffect(id: "filter", in: ns) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

extension SpendingFilter {
    var label: String {
        switch self {
        case .todos: "Todos"
        case .fixos: "Fixos"
        case .variaveis: "Variáveis"
        case .pendentes: "Não confirmados"
        }
    }
}

/// Linha de lançamento: ícone, descrição, meta, valor e status. Toque confirma/desconfirma.
struct EntryRow: View {
    @Environment(AppStore.self) private var store
    let entry: Entry
    let meta: String
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                if let c = store.ledger.category(entry.categoryId) { CategoryIcon(c) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.description).textStyle(15, .semibold).foregroundStyle(.ink).lineLimit(1)
                    Text(meta).textStyle(12.5).foregroundStyle(.inkTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text((entry.estimated ? "~" : "") + BRL.format(entry.amountCents))
                        .textStyle(15, .semibold).monospacedDigit().foregroundStyle(.ink)
                    Text(entry.confirmed ? "confirmado" : "a confirmar")
                        .textStyle(11, .semibold)
                        .foregroundStyle(entry.confirmed ? Color.positive : Color.warning)
                        .contentTransition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint(entry.confirmed ? "Toque para desfazer a confirmação" : "Toque para confirmar")
    }
}
