/// Teclado do lançamento rápido: "1", "2", …, ",", "del".
/// Mesmas regras do protótipo: uma vírgula, dois decimais, até 7 dígitos.
public struct AmountInput: Hashable, Sendable {
    public enum Key: Hashable, Sendable {
        case digit(Int)
        case comma
        case delete
    }

    /// Texto cru, como digitado: "1234,5"
    public private(set) var raw: String

    public init(raw: String = "") { self.raw = raw }

    public init(_ money: Money) {
        let c = money.magnitude.cents
        raw = c % 100 == 0 ? "\(c / 100)" : "\(c / 100)," + BRL.twoDigits(c % 100)
    }

    public var isEmpty: Bool { raw.isEmpty }

    public var money: Money { BRL.parse(raw) ?? .zero }

    /// Texto exibido: "1.234,5" (agrupa milhar, mantém a vírgula enquanto digita)
    public var display: String {
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        let intPart = Int(parts.first.map(String.init) ?? "") ?? 0
        let head = BRL.grouped(intPart)
        return raw.contains(",") ? head + "," + (parts.count > 1 ? String(parts[1]) : "") : head
    }

    @discardableResult
    public mutating func press(_ key: Key) -> Bool {
        switch key {
        case .delete:
            guard !raw.isEmpty else { return false }
            raw.removeLast()
        case .comma:
            guard !raw.contains(",") else { return false }
            raw = (raw.isEmpty ? "0" : raw) + ","
        case .digit(let d):
            precondition((0...9).contains(d))
            if let comma = raw.firstIndex(of: ",") {
                guard raw[raw.index(after: comma)...].count < 2 else { return false }
            }
            guard raw.replacingOccurrences(of: ",", with: "").count < 7 else { return false }
            if raw == "0" { raw = "" }
            raw += String(d)
        }
        return true
    }
}
