import LastroKit
import SwiftUI

/// Para onde um toque na Home leva.
enum Route: Hashable {
    case categoria(UUID)
    case cartoes, recibos, fixas, dividas, metas, ajustes
    case planejar(YearMonth)
}

enum HomeAction: Hashable {
    case push(Route)
    case spending(SpendingFilter)
    case history
    case pilot
}

enum SpendingFilter: String, CaseIterable, Hashable {
    case todos, fixos, variaveis, pendentes
}

/// Tudo que a Home mostra, calculado do Ledger. Mesmas contas e textos do protótipo.
struct HomeModel {
    enum Mode { case current, closed, plan }

    struct Hero: Hashable {
        let label: String
        let value: Money
        let sub: String
    }

    struct Segment: Identifiable, Hashable {
        let label: String
        let weight: Money
        let color: Color
        let text: String
        var id: String { label }
    }

    struct Shortcut: Identifiable, Hashable {
        let label: String
        let value: String
        let sub: String
        let action: HomeAction
        var id: String { label }
    }

    struct CategoryCard: Identifiable, Hashable {
        let category: BudgetCategory
        let amount: String
        let of: String
        let fraction: Double
        let percentText: String
        let barColor: Color
        let sub: String
        let subColor: Color
        var id: UUID { category.id }
    }

    struct PendingRow: Identifiable, Hashable {
        let entry: Entry
        let category: BudgetCategory?
        let meta: String
        let value: String
        let tag: (text: String, isApproval: Bool)?
        var id: UUID { entry.id }

        static func == (a: Self, b: Self) -> Bool { a.entry == b.entry && a.meta == b.meta && a.value == b.value }
        func hash(into h: inout Hasher) { h.combine(entry) }
    }

    struct Dot: Identifiable, Hashable {
        let id: UUID
        let size: CGFloat
        let color: Color
    }

    struct Miudezas: Hashable {
        let title: String
        let sub: String
        let dots: [Dot]
    }

    struct RailMonth: Identifiable, Hashable {
        let month: YearMonth
        let mode: Mode
        var id: YearMonth { month }
    }

    let mode: Mode
    let month: YearMonth
    let subtitle: String
    let heroes: [Hero]
    let segments: [Segment]
    let shortcuts: [Shortcut]
    let categoryCards: [CategoryCard]
    let categoriesRight: String
    let pending: [PendingRow]
    let pendingCount: Int
    let pilotLine: String
    let miudezas: Miudezas?
    let rail: [RailMonth]
    let receiptsCount: Int

    // swiftlint:disable:next function_body_length
    init(ledger: Ledger, selected: YearMonth, today: (month: YearMonth, day: Int)) {
        let mode = Self.mode(of: selected, ledger: ledger, current: today.month)
        self.mode = mode
        self.month = selected
        self.rail = (-2...3).map { today.month.adding(months: $0) }
            .map { RailMonth(month: $0, mode: Self.mode(of: $0, ledger: ledger, current: today.month)) }
        self.receiptsCount = ledger.pendingReceipts.count

        let bills = ledger.activeBills
        let R = BRL.format, R0 = BRL.rounded

        switch mode {
        case .current:
            let m = CurrentMonth(ledger, month: selected, today: today.day)
            subtitle = "dia \(today.day) · faltam \(m.daysLeft) dias"
            heroes = [
                Hero(label: "Sobra prevista", value: m.forecastLeftover, sub: "se o resto do mês sair como planejado"),
                Hero(label: "Saldo confirmado agora", value: m.confirmedBalance, sub: "o que entrou menos o que você já confirmou"),
                Hero(label: "Falta pagar das fixas", value: m.pendingFixedTotal,
                     sub: "\(m.pendingFixed.count) contas até o dia \(m.daysInMonth)"),
            ]
            let stillOut = max(.zero, m.forecastOut - m.confirmedTotal)
            segments = [
                Segment(label: "Confirmado", weight: m.confirmedTotal, color: .ink, text: R0(m.confirmedTotal)),
                Segment(label: "Ainda sai", weight: stillOut, color: .ink.opacity(0.2), text: R0(m.forecastOut - m.confirmedTotal)),
                Segment(label: "Sobra", weight: max(.zero, m.forecastLeftover), color: .accent, text: R0(m.forecastLeftover)),
            ]
            shortcuts = [
                Shortcut(label: "Pode gastar hoje", value: R(m.canSpendToday),
                         sub: "no variável, até o dia \(m.daysInMonth)", action: .spending(.variaveis)),
                Shortcut(label: "Faturas abertas", value: R0(m.openStatements),
                         sub: "em \(ledger.activeCards.count) cartões", action: .push(.cartoes)),
            ]
            categoryCards = m.categories.map { s in
                CategoryCard(category: s.category, amount: R0(s.spent), of: "/ " + BRL.number(s.budget),
                             fraction: s.fraction, percentText: "\(s.percent)%",
                             barColor: s.isOver ? .negative : .category(s.category.hue),
                             sub: s.isOver ? "passou " + R(-s.left) : "sobra " + R(s.left),
                             subColor: s.isOver ? .negative : .inkTertiary)
            }
            categoriesRight = "\(R0(m.totalSpent)) de \(R0(m.totalBudget))"

            let all = m.pending
            pendingCount = all.count
            pending = all.prefix(3).map { e in
                let approve = m.needsApproval(e)
                let when = e.day > today.day ? "vence dia \(e.day)" : Ledger.dayLabel(e.day, today: today.day)
                return PendingRow(entry: e, category: ledger.category(e.categoryId),
                                  meta: "\(when) · \(ledger.paidWith(e))",
                                  value: (e.estimated ? "~" : "") + R(e.amountCents),
                                  tag: approve ? ("Aprovar", true) : e.estimated ? ("estimado", false) : nil)
            }

            let next = m.nextAutopay.map { " · próxima: \($0.name), dia \($0.dueDay)" } ?? ""
            pilotLine = "\(R0(m.autopaidTotal)) pagos sozinhos\(next)"

            let small = m.smallSpends
            let total = small.sum(\.amountCents)
            let comparison: String
            if let luz = bills.first(where: { $0.name == "Luz" })?.amountCents, luz.cents > 0 {
                comparison = total > luz ? "Mais que a conta de luz inteira."
                    : Double(total.cents) > Double(luz.cents) * 0.8 ? "Quase uma conta de luz."
                    : "\(Int((Double(total.cents) / Double(luz.cents) * 100).rounded()))% de uma conta de luz."
            } else {
                comparison = ""
            }
            miudezas = Miudezas(
                title: "\(R(total)) em \(small.count) gastos pequenos",
                sub: "Tudo abaixo de R$ 50 em \(selected.name.lowercased()). \(comparison)",
                dots: small.map { e in
                    Dot(id: e.id, size: 7 + CGFloat(e.amountCents.cents) / 5_000 * 13,
                        color: .category(ledger.category(e.categoryId)?.hue ?? 0))
                })

        case .closed:
            let m = ClosedMonth(ledger, month: selected)
            let left = m.leftover
            subtitle = "mês fechado · \(selected.year)"
            heroes = [
                Hero(label: "Sobra realizada", value: left, sub: left.isNegative ? "o mês fechou no vermelho" : "o que ficou na conta"),
                Hero(label: "Entrou", value: m.income, sub: "salários e VR"),
                Hero(label: "Saiu", value: m.out, sub: "tudo confirmado"),
            ]
            segments = [
                Segment(label: "Saiu", weight: m.out, color: .ink, text: R0(m.out)),
                Segment(label: left.isNegative ? "Faltou" : "Sobrou", weight: left.magnitude,
                        color: left.isNegative ? .negative : .positive, text: R0(left)),
            ]
            shortcuts = [Shortcut(label: "Só leitura", value: "\(selected.name) fechou", sub: "confirmados e travados", action: .history)]
            categoryCards = m.categories.map { s in
                let l = s.left
                return CategoryCard(category: s.category, amount: R0(s.spent), of: "/ " + BRL.number(s.budget),
                                    fraction: s.fraction, percentText: "\(s.percent)%",
                                    barColor: l.cents < 0 ? .negative : .category(s.category.hue),
                                    sub: l.cents < 0 ? "passou " + R(-l) : l.cents == 0 ? "no orçamento" : "sobrou " + R(l),
                                    subColor: l.cents < 0 ? .negative : .inkTertiary)
            }
            categoriesRight = R0(m.out) + " no total"
            pending = []
            pendingCount = 0
            pilotLine = ""
            miudezas = nil

        case .plan:
            let p = PlannedMonth(ledger, month: selected)
            let fixed = p.fixedTotal
            subtitle = "planejamento · \(selected.year)"
            heroes = [
                Hero(label: "Sobra planejada", value: p.leftover, sub: "renda menos o que você planejou"),
                Hero(label: "Fixas já copiadas", value: ledger.billsTotal, sub: "\(bills.count) contas nasceram sozinhas"),
                Hero(label: "Dá pra guardar", value: p.savable, sub: "70% da sobra, deixando 30% de folga"),
            ]
            segments = [
                Segment(label: "Fixas", weight: fixed, color: .ink, text: R0(fixed)),
                Segment(label: "Variáveis", weight: max(.zero, p.total - fixed), color: .ink.opacity(0.2), text: R0(p.total - fixed)),
                Segment(label: "Sobra", weight: max(.zero, p.leftover), color: .accent, text: R0(p.leftover)),
            ]
            shortcuts = [
                Shortcut(label: "Contas fixas já copiadas", value: "\(bills.count) · \(R0(ledger.billsTotal))",
                         sub: "nada pra recriar", action: .push(.fixas)),
                Shortcut(label: "Ajustar orçamento", value: "Planejar", sub: "passo de R$ 50", action: .push(.planejar(selected))),
            ]
            categoryCards = ledger.activeCategories.map { c in
                CategoryCard(category: c, amount: R0(p.budget(c.id)), of: "planejado", fraction: 0, percentText: "",
                             barColor: .category(c.hue), sub: c.budgetOrigin, subColor: .inkTertiary)
            }
            categoriesRight = "toque para ajustar"
            pending = []
            pendingCount = 0
            pilotLine = "\(bills.filter(\.autopay).count) contas vão se pagar sozinhas"
            miudezas = nil
        }
    }

    static func mode(of m: YearMonth, ledger: Ledger, current: YearMonth) -> Mode {
        switch ledger.month(m)?.status {
        case .closed: .closed
        case .open: m == current ? .current : m < current ? .closed : .plan
        case .planning: .plan
        case nil: m < current ? .closed : m == current ? .current : .plan
        }
    }

    func action(for card: CategoryCard) -> HomeAction? {
        switch mode {
        case .current: .push(.categoria(card.category.id))
        case .plan: .push(.planejar(month))
        case .closed: nil
        }
    }
}
