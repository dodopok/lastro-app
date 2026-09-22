import Foundation

/// Tudo que o app sabe sobre o dinheiro do usuário. Valor puro: as telas
/// derivam os números daqui (as mesmas contas do protótipo), o cache local e
/// o sync só alimentam esta estrutura.
public struct Ledger: Sendable, Hashable {
    public var profile: Profile
    public var categories: [BudgetCategory]
    public var cards: [Card]
    public var carryovers: [CardCarryover]
    public var bills: [Bill]
    public var months: [Month]
    public var budgets: [MonthBudget]
    public var extras: [MonthExtra]
    public var entries: [Entry]
    public var receipts: [Receipt]
    public var debts: [Debt]
    public var goals: [Goal]

    public init(profile: Profile, categories: [BudgetCategory] = [], cards: [Card] = [], carryovers: [CardCarryover] = [],
                bills: [Bill] = [], months: [Month] = [], budgets: [MonthBudget] = [], extras: [MonthExtra] = [],
                entries: [Entry] = [], receipts: [Receipt] = [], debts: [Debt] = [], goals: [Goal] = []) {
        self.profile = profile
        self.categories = categories
        self.cards = cards
        self.carryovers = carryovers
        self.bills = bills
        self.months = months
        self.budgets = budgets
        self.extras = extras
        self.entries = entries
        self.receipts = receipts
        self.debts = debts
        self.goals = goals
    }

    // MARK: consultas

    public var activeCategories: [BudgetCategory] {
        categories.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }
    public var activeCards: [Card] { cards.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position } }
    public var activeBills: [Bill] { bills.filter { $0.deletedAt == nil }.sorted { ($0.dueDay, $0.name) < ($1.dueDay, $1.name) } }
    public var pendingReceipts: [Receipt] { receipts.filter { $0.status == .pending && $0.deletedAt == nil } }

    public func category(_ id: UUID) -> BudgetCategory? { categories.first { $0.id == id } }
    public func card(_ id: UUID) -> Card? { cards.first { $0.id == id } }
    public func bill(_ id: UUID) -> Bill? { bills.first { $0.id == id } }
    public func month(_ m: YearMonth) -> Month? { months.first { $0.month == m && $0.deletedAt == nil } }

    public func entries(in m: YearMonth) -> [Entry] {
        entries.filter { $0.month == m && $0.deletedAt == nil }
    }

    public func income(in m: YearMonth) -> Money {
        month(m)?.incomeCents ?? profile.monthlyIncomeCents
    }

    public func budget(for categoryId: UUID, in m: YearMonth) -> Money {
        budgets.first { $0.month == m && $0.categoryId == categoryId && $0.deletedAt == nil }?.amountCents
            ?? category(categoryId)?.defaultBudgetCents ?? .zero
    }

    public func extras(in m: YearMonth) -> [MonthExtra] {
        extras.filter { $0.month == m && $0.deletedAt == nil }
    }

    public func carryover(card: UUID, in m: YearMonth) -> Money {
        carryovers.first { $0.cardId == card && $0.month == m && $0.deletedAt == nil }?.amountCents ?? .zero
    }

    public var billsTotal: Money { activeBills.sum(\.amountCents) }

    /// "Dia 21" · "ontem" · "hoje" relativo ao dia corrente.
    public static func dayLabel(_ day: Int, today: Int) -> String {
        day == today ? "hoje" : day == today - 1 ? "ontem" : "dia \(day)"
    }

    /// Como foi pago: nome do cartão ou método.
    public func paidWith(_ e: Entry) -> String {
        e.cardId.flatMap { card($0)?.name } ?? e.method.label
    }
}

// MARK: - Mês corrente

public struct CategoryStatus: Sendable, Hashable, Identifiable {
    public let category: BudgetCategory
    public let spent: Money
    public let budget: Money
    public var id: UUID { category.id }
    public var left: Money { budget - spent }
    public var isOver: Bool { left.isNegative }
    /// 0...1 (recortado) para a barra; `percent` sem recorte para o texto.
    public var fraction: Double { budget.cents > 0 ? min(1, Double(spent.cents) / Double(budget.cents)) : 0 }
    public var percent: Int { budget.cents > 0 ? Int((Double(spent.cents) / Double(budget.cents) * 100).rounded()) : 0 }
}

public struct CurrentMonth: Sendable {
    public let ledger: Ledger
    public let month: YearMonth
    public let today: Int
    public let entries: [Entry]
    public let income: Money

    public init(_ ledger: Ledger, month: YearMonth, today: Int) {
        self.ledger = ledger
        self.month = month
        self.today = today
        self.entries = ledger.entries(in: month)
        self.income = ledger.income(in: month)
    }

    public var daysInMonth: Int { month.numberOfDays }
    public var daysLeft: Int { daysInMonth - today }

    public func spent(_ categoryId: UUID) -> Money {
        entries.filter { $0.categoryId == categoryId }.sum(\.amountCents)
    }

    public var categories: [CategoryStatus] {
        ledger.activeCategories.map {
            CategoryStatus(category: $0, spent: spent($0.id), budget: ledger.budget(for: $0.id, in: month))
        }
    }

    public var confirmedTotal: Money { entries.filter(\.confirmed).sum(\.amountCents) }
    public var totalSpent: Money { entries.sum(\.amountCents) }
    public var totalBudget: Money { categories.sum(\.budget) }

    /// O que o mês vai custar: em cada categoria, o maior entre orçamento e gasto.
    public var forecastOut: Money { categories.sum { max($0.budget, $0.spent) } }

    /// Sobra prevista: se o resto do mês sair como planejado.
    public var forecastLeftover: Money { income - forecastOut }

    /// Saldo confirmado agora: o que entrou menos o que você já confirmou.
    public var confirmedBalance: Money { income - confirmedTotal }

    /// Fixas e parcelas ainda não confirmadas.
    public var pendingFixed: [Entry] { entries.filter { !$0.confirmed && $0.kind != .variavel } }
    public var pendingFixedTotal: Money { pendingFixed.sum(\.amountCents) }

    /// Tudo que falta confirmar, por dia (no mesmo dia, contas fixas primeiro).
    public var pending: [Entry] {
        entries.filter { !$0.confirmed }.sorted {
            ($0.day, $0.billId == nil ? 1 : 0, $0.description) < ($1.day, $1.billId == nil ? 1 : 0, $1.description)
        }
    }

    /// Quanto ainda cabe nas categorias variáveis e de reserva.
    public var flexibleRemaining: Money {
        categories.filter { $0.category.nature.isFlexible }.sum { max(.zero, $0.left) }
    }

    /// Pode gastar hoje: o que sobra no variável dividido pelos dias restantes (hoje incluso).
    public var canSpendToday: Money { flexibleRemaining.divided(by: max(1, daysInMonth - today + 1)) }

    public func statement(card: UUID) -> Money {
        ledger.carryover(card: card, in: month) + entries.filter { $0.cardId == card }.sum(\.amountCents)
    }

    public var openStatements: Money { ledger.activeCards.sum { statement(card: $0.id) } }

    /// Miudezas: gastos variáveis abaixo de R$ 50.
    public static let smallSpendLimit = Money(cents: 5_000)
    public var smallSpends: [Entry] {
        entries.filter { $0.kind == .variavel && $0.amountCents < Self.smallSpendLimit }.sorted { $0.day < $1.day }
    }

    /// Acima do limite, com piloto e já vencida: o app pede Face ID ("Aprovar").
    public func needsApproval(_ e: Entry) -> Bool {
        guard !e.confirmed, let b = e.billId.flatMap({ ledger.bill($0) }), b.autopay else { return false }
        return e.amountCents > ledger.profile.approvalThresholdCents && e.day <= today
    }

    public var autopaidTotal: Money {
        entries.filter { e in e.confirmed && (e.billId.flatMap({ ledger.bill($0) })?.autopay ?? false) }.sum(\.amountCents)
    }

    public var nextAutopay: Bill? {
        ledger.activeBills.filter { $0.autopay && $0.dueDay > today }.min { $0.dueDay < $1.dueDay }
    }

    /// Trava de segurança: o piloto só paga com o saldo confirmado acima dela.
    public var isAboveSafetyFloor: Bool { confirmedBalance >= ledger.profile.safetyFloorCents }
}

// MARK: - Mês fechado

public struct ClosedMonth: Sendable {
    public let month: YearMonth
    public let income: Money
    public let categories: [CategoryStatus]

    public init(_ ledger: Ledger, month: YearMonth) {
        self.month = month
        self.income = ledger.income(in: month)
        let entries = ledger.entries(in: month)
        self.categories = ledger.activeCategories.map { c in
            CategoryStatus(category: c, spent: entries.filter { $0.categoryId == c.id }.sum(\.amountCents),
                           budget: ledger.budget(for: c.id, in: month))
        }
    }

    public var out: Money { categories.sum(\.spent) }
    public var leftover: Money { income - out }
}

// MARK: - Planejamento

public struct PlannedMonth: Sendable {
    public let ledger: Ledger
    public let month: YearMonth

    public init(_ ledger: Ledger, month: YearMonth) {
        self.ledger = ledger
        self.month = month
    }

    public var income: Money { ledger.income(in: month) }
    public func budget(_ categoryId: UUID) -> Money { ledger.budget(for: categoryId, in: month) }
    public var extras: [MonthExtra] { ledger.extras(in: month) }

    public var total: Money {
        ledger.activeCategories.sum { budget($0.id) } + extras.sum(\.amountCents)
    }
    public var fixedTotal: Money {
        ledger.activeCategories.filter { !$0.nature.isFlexible }.sum { budget($0.id) }
    }
    public var leftover: Money { income - total }

    /// Dá pra guardar: 70% da sobra, deixando 30% de folga.
    public var savable: Money { max(.zero, leftover.scaled(by: 0.7)) }

    /// Diferença vs. o orçamento padrão da categoria (para "+R$ 50 vs. setembro").
    public func delta(_ c: BudgetCategory) -> Money { budget(c.id) - c.defaultBudgetCents }
}

// MARK: - Histórico do ano

public struct YearHistory: Sendable {
    public struct Point: Sendable, Hashable, Identifiable {
        public let month: YearMonth
        public let leftover: Money
        public let isForecast: Bool
        public var id: YearMonth { month }
    }

    public let points: [Point]

    /// Janeiro até o mês corrente (este como previsão).
    public init(_ ledger: Ledger, current: YearMonth, today: Int) {
        var pts: [Point] = []
        var m = YearMonth(year: current.year, month: 1)
        while m < current {
            pts.append(Point(month: m, leftover: ClosedMonth(ledger, month: m).leftover, isForecast: false))
            m = m.next
        }
        pts.append(Point(month: current, leftover: CurrentMonth(ledger, month: current, today: today).forecastLeftover,
                         isForecast: true))
        points = pts
    }

    public var total: Money { points.sum(\.leftover) }
    public var maxMagnitude: Money { points.map(\.leftover.magnitude).max() ?? .zero }
}

// MARK: - Reserva e dívidas

public extension Ledger {
    /// Meses de reserva = guardado na reserva de emergência / custo fixo mensal.
    var emergencyMonths: Double {
        guard let g = goals.first(where: { $0.kind == .emergency && $0.deletedAt == nil }), billsTotal.cents > 0 else { return 0 }
        return Double(g.savedCents.cents) / Double(billsTotal.cents)
    }

    func target(of g: Goal) -> Money { g.targetCents ?? billsTotal * 6 }

    var openDebt: Money { debts.filter { $0.deletedAt == nil }.sum(\.remaining) }
}
