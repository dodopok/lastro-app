/// Um mês do calendário. No banco é o primeiro dia (`2026-09-01`).
public struct YearMonth: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int  // 1...12

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month))
        self.year = year
        self.month = month
    }

    /// Aceita "2026-09-01" ou "2026-09".
    public init?(iso: String) {
        let p = iso.split(separator: "-")
        guard p.count >= 2, let y = Int(p[0]), let m = Int(p[1]), (1...12).contains(m) else { return nil }
        self.init(year: y, month: m)
    }

    public var iso: String { "\(year)-\(month < 10 ? "0" : "")\(month)-01" }

    public var next: YearMonth { month == 12 ? .init(year: year + 1, month: 1) : .init(year: year, month: month + 1) }
    public var previous: YearMonth { month == 1 ? .init(year: year - 1, month: 12) : .init(year: year, month: month - 1) }

    public func adding(months n: Int) -> YearMonth {
        let total = year * 12 + (month - 1) + n
        return .init(year: total / 12, month: total % 12 + 1)
    }

    public var numberOfDays: Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    public static let names = ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
                               "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"]
    public static let shortNames = ["JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ"]

    /// "Setembro"
    public var name: String { Self.names[month - 1] }
    /// "SET"
    public var shortName: String { Self.shortNames[month - 1] }

    public static func < (a: YearMonth, b: YearMonth) -> Bool {
        (a.year, a.month) < (b.year, b.month)
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let v = YearMonth(iso: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "mês inválido: \(s)"))
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }
}
