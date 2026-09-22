/// Dinheiro em centavos. Nunca Double para guardar valor.
public struct Money: Hashable, Comparable, Sendable, Codable {
    public var cents: Int

    public init(cents: Int) { self.cents = cents }

    /// Para literais de seed e testes: `Money(reais: 412.5)`.
    public init(reais: Double) { self.cents = Int((reais * 100).rounded()) }

    public static let zero = Money(cents: 0)

    public var isNegative: Bool { cents < 0 }
    public var magnitude: Money { Money(cents: abs(cents)) }
    public var reais: Double { Double(cents) / 100 }

    public static func + (a: Money, b: Money) -> Money { Money(cents: a.cents + b.cents) }
    public static func - (a: Money, b: Money) -> Money { Money(cents: a.cents - b.cents) }
    public static prefix func - (a: Money) -> Money { Money(cents: -a.cents) }
    public static func += (a: inout Money, b: Money) { a.cents += b.cents }
    public static func -= (a: inout Money, b: Money) { a.cents -= b.cents }
    public static func * (a: Money, k: Int) -> Money { Money(cents: a.cents * k) }
    public static func < (a: Money, b: Money) -> Bool { a.cents < b.cents }

    /// Divide arredondando para o centavo mais próximo.
    public func divided(by n: Int) -> Money {
        precondition(n > 0)
        return Money(cents: Int((Double(cents) / Double(n)).rounded()))
    }

    public func scaled(by factor: Double) -> Money {
        Money(cents: Int((Double(cents) * factor).rounded()))
    }

    /// Desfaz a encodificação JSON do Postgres (bigint) sem perder o tipo.
    public init(from decoder: Decoder) throws {
        cents = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(cents)
    }
}

extension Sequence {
    public func sum(_ value: (Element) -> Money) -> Money {
        reduce(.zero) { $0 + value($1) }
    }
}

// MARK: - Formatação pt-BR (determinística, sem NumberFormatter)

public enum BRL {
    /// Menos tipográfico, como no design.
    public static let minus = "\u{2212}"

    /// "R$ 12.345,60" · "−R$ 0,50"
    public static func format(_ m: Money) -> String {
        (m.isNegative ? minus : "") + "R$ " + digits(m.magnitude)
    }

    /// Sem centavos, arredondado: "R$ 1.235" · "−R$ 1.235"
    public static func rounded(_ m: Money) -> String {
        let r = roundedReais(m)
        return (r < 0 ? minus : "") + "R$ " + grouped(abs(r))
    }

    /// Só o número, sem "R$": "1.235"
    public static func number(_ m: Money) -> String {
        let r = roundedReais(m)
        return (r < 0 ? minus : "") + grouped(abs(r))
    }

    /// "12.345,60" (sem sinal)
    public static func digits(_ m: Money) -> String {
        let c = abs(m.cents)
        return grouped(c / 100) + "," + twoDigits(c % 100)
    }

    /// Partes do número herói: sinal, inteiro agrupado e centavos atenuados.
    public static func heroParts(_ m: Money) -> (sign: String, integer: String, cents: String) {
        let c = abs(m.cents)
        return (m.isNegative ? minus : "", grouped(c / 100), "," + twoDigits(c % 100))
    }

    /// Converte o texto de um campo ("1.234,5" · "412,50" · "96") em dinheiro.
    public static func parse(_ text: String) -> Money? {
        let clean = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        let parts = clean.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count <= 2, let intPart = Int(parts[0].isEmpty ? "0" : String(parts[0])), intPart >= 0 else {
            return nil
        }
        var cents = intPart * 100
        if parts.count == 2 {
            let frac = String(parts[1].prefix(2))
            guard frac.allSatisfy(\.isNumber) else { return nil }
            let padded = frac.padding(toLength: 2, withPad: "0", startingAt: 0)
            cents += Int(padded) ?? 0
        }
        return Money(cents: cents)
    }

    static func roundedReais(_ m: Money) -> Int {
        Int((Double(m.cents) / 100).rounded(.toNearestOrAwayFromZero))
    }

    static func grouped(_ n: Int) -> String {
        let s = String(n)
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, (s.count - i) % 3 == 0 { out.append(".") }
            out.append(ch)
        }
        return out
    }

    static func twoDigits(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}

extension Money: CustomStringConvertible {
    public var description: String { BRL.format(self) }
}
