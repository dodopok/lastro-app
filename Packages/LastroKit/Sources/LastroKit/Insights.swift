import Foundation

/// Textos derivados dos dados (nada de frase fixa do protótipo).
public enum Insights {
    static let weekdays = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]

    /// Dia da semana (0 = domingo) de um dia do mês.
    public static func weekday(_ month: YearMonth, day: Int) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: month.year, month: month.month, day: day))!
        return cal.component(.weekday, from: date) - 1
    }

    /// "Padrão" do detalhe de categoria.
    public static func category(_ c: BudgetCategory, entries: [Entry], month: YearMonth, today: Int) -> String {
        guard c.nature.isFlexible else {
            return "Categoria fixa: o valor se repete todo mês e o mês novo já nasce com ela."
        }
        guard entries.count >= 3 else {
            return entries.isEmpty ? "Nada lançado aqui em \(month.name.lowercased()) ainda."
                : "Só \(entries.count) lançamento\(entries.count == 1 ? "" : "s") até agora. Cedo para ver padrão."
        }
        var head = "\(entries.count) lançamentos em \(today) dias."
        var byDay = [Int: Int]()
        for e in entries { byDay[weekday(month, day: e.day), default: 0] += 1 }
        let top = byDay.sorted { ($0.value, -$0.key) > ($1.value, -$1.key) }.prefix(2)
        let share = Double(top.map(\.value).reduce(0, +)) / Double(entries.count)
        if top.count == 2, share >= 0.5 {
            let names = top.map { weekdays[$0.key] }
            head += " \(names[0].capitalized) e \(names[1]) concentram \(Int((share * 100).rounded()))%."
        }
        if let biggest = entries.max(by: { $0.amountCents < $1.amountCents }) {
            head += " O maior foi \(biggest.description), \(BRL.format(biggest.amountCents)) no dia \(biggest.day)."
        }
        return head
    }

    /// Aviso dos cartões: quantos vencimentos diferentes.
    public static func cards(_ cards: [Card]) -> String {
        let dues = Set(cards.map(\.dueDay)).count
        let n = cards.count
        return "Seus \(n) cartões têm \(dues) vencimento\(dues == 1 ? "" : "s") diferente\(dues == 1 ? "" : "s"). "
            + "Compra depois do fechamento só cai na fatura seguinte, por isso o mês parece não bater."
    }
}

// MARK: - Dívidas

public struct DebtSummary: Sendable {
    public let open: Money
    /// Soma das parcelas mensais ativas.
    public let monthly: Money
    public let freeAt: YearMonth?

    public init(_ ledger: Ledger, current: YearMonth) {
        let active = ledger.debts.filter { $0.deletedAt == nil }
        open = active.sum(\.remaining)
        monthly = active.filter { !$0.isPaidOff }.sum(\.installmentCents)
        let longest = active.map { $0.installmentsTotal - $0.installmentsPaid }.max() ?? 0
        freeAt = longest > 0 ? current.adding(months: longest) : nil
    }

    public func shareOfIncome(_ income: Money) -> Double {
        income.cents > 0 ? Double(monthly.cents) / Double(income.cents) : 0
    }
}

// MARK: - Histórico: detalhe de um mês

public struct MonthDetail: Sendable {
    public struct Top: Sendable, Hashable, Identifiable {
        public let category: BudgetCategory
        public let amount: Money
        public var id: UUID { category.id }
    }

    public let month: YearMonth
    public let isForecast: Bool
    public let income: Money
    public let out: Money
    public let top: [Top]
    public var leftover: Money { income - out }

    public init(_ ledger: Ledger, month: YearMonth, current: YearMonth, today: Int) {
        self.month = month
        isForecast = month == current
        let spent: [CategoryStatus]
        if month == current {
            let m = CurrentMonth(ledger, month: month, today: today)
            income = m.income
            out = m.forecastOut
            spent = m.categories.map { CategoryStatus(category: $0.category, spent: max($0.budget, $0.spent), budget: $0.budget) }
        } else {
            let m = ClosedMonth(ledger, month: month)
            income = m.income
            out = m.out
            spent = m.categories
        }
        top = spent.sorted { $0.spent > $1.spent }.prefix(3).map { Top(category: $0.category, amount: $0.spent) }
    }
}
