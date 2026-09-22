import Foundation

// Espelho das tabelas do Supabase (supabase/migrations). Codable com
// snake_case: use `LastroCoding.decoder` / `.encoder`.

public enum CategoryNature: String, Codable, Sendable, CaseIterable {
    case fixo, variavel, parcelado, reserva

    /// Categorias que entram no "pode gastar hoje".
    public var isFlexible: Bool { self == .variavel || self == .reserva }
}

public enum PayMethod: String, Codable, Sendable, CaseIterable {
    case pix, boleto, debito, cartao

    public var label: String {
        switch self {
        case .pix: "Pix"
        case .boleto: "Boleto"
        case .debito: "Débito"
        case .cartao: "Cartão"
        }
    }
}

public enum TxKind: String, Codable, Sendable { case fixa, parcela, variavel }
public enum TxSource: String, Codable, Sendable { case manual, scan, share, bill, `import` }
public enum MonthStatus: String, Codable, Sendable { case planning, open, closed }
public enum ReceiptStatus: String, Codable, Sendable { case pending, saved, discarded }
public enum GoalKind: String, Codable, Sendable { case emergency, custom }
public enum PaymentStatus: String, Codable, Sendable {
    case scheduled, awaitingApproval = "awaiting_approval", processing, paid, failed, blocked
}

public struct Profile: Codable, Sendable, Hashable {
    public var userId: UUID
    public var displayName: String?
    public var timezone: String
    public var monthlyIncomeCents: Money
    public var safetyFloorCents: Money
    public var approvalThresholdCents: Money
    public var updatedAt: Date?

    public init(userId: UUID, displayName: String? = nil, timezone: String = "America/Sao_Paulo",
                monthlyIncomeCents: Money, safetyFloorCents: Money = Money(cents: 300_000),
                approvalThresholdCents: Money = Money(cents: 100_000), updatedAt: Date? = nil) {
        self.userId = userId
        self.displayName = displayName
        self.timezone = timezone
        self.monthlyIncomeCents = monthlyIncomeCents
        self.safetyFloorCents = safetyFloorCents
        self.approvalThresholdCents = approvalThresholdCents
        self.updatedAt = updatedAt
    }
}

public struct BudgetCategory: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var slug: String
    public var name: String
    public var hue: Double
    public var nature: CategoryNature
    public var defaultBudgetCents: Money
    public var symbol: String
    public var position: Int
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), slug: String, name: String, hue: Double, nature: CategoryNature,
                defaultBudgetCents: Money, symbol: String, position: Int, updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.slug = slug
        self.name = name
        self.hue = hue
        self.nature = nature
        self.defaultBudgetCents = defaultBudgetCents
        self.symbol = symbol
        self.position = position
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Legenda da origem do orçamento no planejamento.
    public var budgetOrigin: String {
        switch nature {
        case .fixo: "repete todo mês"
        case .variavel: "média dos 3 meses"
        case .parcelado: "parcelas ativas"
        case .reserva: "reserva fixa"
        }
    }
}

public struct Card: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var subtitle: String?
    public var hue: Double
    public var limitCents: Money
    public var closingDay: Int
    public var dueDay: Int
    public var position: Int
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), name: String, subtitle: String?, hue: Double, limitCents: Money,
                closingDay: Int, dueDay: Int, position: Int, updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.hue = hue
        self.limitCents = limitCents
        self.closingDay = closingDay
        self.dueDay = dueDay
        self.position = position
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct CardCarryover: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var cardId: UUID
    public var month: YearMonth
    public var amountCents: Money
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), cardId: UUID, month: YearMonth, amountCents: Money) {
        self.id = id
        self.cardId = cardId
        self.month = month
        self.amountCents = amountCents
    }
}

/// Conta fixa.
public struct Bill: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var categoryId: UUID
    public var dueDay: Int
    public var amountCents: Money
    public var isVariable: Bool
    public var autopay: Bool
    public var method: PayMethod
    public var pixKey: String?
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), name: String, categoryId: UUID, dueDay: Int, amountCents: Money,
                isVariable: Bool = false, autopay: Bool = false, method: PayMethod = .pix, pixKey: String? = nil,
                updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.categoryId = categoryId
        self.dueDay = dueDay
        self.amountCents = amountCents
        self.isVariable = isVariable
        self.autopay = autopay
        self.method = method
        self.pixKey = pixKey
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct Month: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var month: YearMonth
    public var status: MonthStatus
    public var incomeCents: Money
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), month: YearMonth, status: MonthStatus, incomeCents: Money) {
        self.id = id
        self.month = month
        self.status = status
        self.incomeCents = incomeCents
    }
}

public struct MonthBudget: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var month: YearMonth
    public var categoryId: UUID
    public var amountCents: Money
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), month: YearMonth, categoryId: UUID, amountCents: Money) {
        self.id = id
        self.month = month
        self.categoryId = categoryId
        self.amountCents = amountCents
    }
}

public struct MonthExtra: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var month: YearMonth
    public var name: String
    public var amountCents: Money
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), month: YearMonth, name: String, amountCents: Money) {
        self.id = id
        self.month = month
        self.name = name
        self.amountCents = amountCents
    }
}

/// Lançamento (tabela `transactions`).
public struct Entry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var month: YearMonth
    public var day: Int
    public var description: String
    public var categoryId: UUID
    public var amountCents: Money
    public var method: PayMethod
    public var cardId: UUID?
    public var confirmed: Bool
    public var kind: TxKind
    public var source: TxSource
    public var billId: UUID?
    public var estimated: Bool
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), month: YearMonth, day: Int, description: String, categoryId: UUID,
                amountCents: Money, method: PayMethod, cardId: UUID? = nil, confirmed: Bool = true,
                kind: TxKind = .variavel, source: TxSource = .manual, billId: UUID? = nil, estimated: Bool = false,
                updatedAt: Date? = nil, deletedAt: Date? = nil) {
        precondition((method == .cartao) == (cardId != nil), "cartão exige cardId")
        self.id = id
        self.month = month
        self.day = day
        self.description = description
        self.categoryId = categoryId
        self.amountCents = amountCents
        self.method = method
        self.cardId = cardId
        self.confirmed = confirmed
        self.kind = kind
        self.source = source
        self.billId = billId
        self.estimated = estimated
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct Receipt: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var merchant: String
    public var originLabel: String
    public var source: TxSource
    public var amountCents: Money
    public var categoryId: UUID?
    public var cardId: UUID?
    public var capturedAt: Date
    public var status: ReceiptStatus
    public var transactionId: UUID?
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), merchant: String, originLabel: String, source: TxSource, amountCents: Money,
                categoryId: UUID?, cardId: UUID?, capturedAt: Date, status: ReceiptStatus = .pending,
                transactionId: UUID? = nil) {
        self.id = id
        self.merchant = merchant
        self.originLabel = originLabel
        self.source = source
        self.amountCents = amountCents
        self.categoryId = categoryId
        self.cardId = cardId
        self.capturedAt = capturedAt
        self.status = status
        self.transactionId = transactionId
    }
}

public struct Debt: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var billId: UUID?
    public var installmentCents: Money
    public var installmentsTotal: Int
    public var installmentsPaid: Int
    public var paidCents: Money
    public var position: Int
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), name: String, description: String?, billId: UUID? = nil, installmentCents: Money,
                installmentsTotal: Int, installmentsPaid: Int, paidCents: Money, position: Int) {
        self.id = id
        self.name = name
        self.description = description
        self.billId = billId
        self.installmentCents = installmentCents
        self.installmentsTotal = installmentsTotal
        self.installmentsPaid = installmentsPaid
        self.paidCents = paidCents
        self.position = position
    }

    public var remaining: Money { installmentCents * (installmentsTotal - installmentsPaid) }
    public var progress: Double { Double(installmentsPaid) / Double(installmentsTotal) }
    public var isPaidOff: Bool { installmentsPaid >= installmentsTotal }
}

public struct Goal: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: GoalKind
    public var name: String
    public var description: String?
    public var targetCents: Money?
    public var savedCents: Money
    public var hue: Double
    public var position: Int
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), kind: GoalKind, name: String, description: String?, targetCents: Money?,
                savedCents: Money, hue: Double, position: Int) {
        self.id = id
        self.kind = kind
        self.name = name
        self.description = description
        self.targetCents = targetCents
        self.savedCents = savedCents
        self.hue = hue
        self.position = position
    }
}

public struct Payment: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var billId: UUID?
    public var transactionId: UUID?
    public var amountCents: Money
    public var method: PayMethod
    public var destination: String
    public var scheduledFor: String
    public var status: PaymentStatus
    public var requiresApproval: Bool
    public var failureReason: String?
    public var updatedAt: Date?
}

public enum LastroCoding {
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = parseTimestamp(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "data inválida: \(s)"))
        }
        return d
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// Postgres devolve "2026-09-22T19:35:03.103854+00:00" (microssegundos).
    public static func parseTimestamp(_ s: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle()
        if let d = try? withFraction.parse(s) { return d }
        if let d = try? plain.parse(s) { return d }
        // Trunca a fração para milissegundos, que o ISO8601FormatStyle entende.
        if let dot = s.firstIndex(of: "."), let tz = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let frac = s[s.index(after: dot)..<tz].prefix(3)
            let fixed = String(s[..<dot]) + "." + String(frac) + String(s[tz...])
            return try? withFraction.parse(fixed)
        }
        return nil
    }
}
