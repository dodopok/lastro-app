import Foundation

/// Uma conta fixa lida da planilha.
public struct ImportedBill: Hashable, Sendable, Identifiable {
    public var id: String { "\(name)|\(amount.cents)|\(dueDay)" }
    public var name: String
    public var amount: Money
    public var categoryName: String?
    public var dueDay: Int
    public var isVariable: Bool

    public init(name: String, amount: Money, categoryName: String?, dueDay: Int, isVariable: Bool) {
        self.name = name
        self.amount = amount
        self.categoryName = categoryName
        self.dueDay = dueDay
        self.isVariable = isVariable
    }
}

/// Importa contas fixas de um CSV exportado da planilha (Excel/Numbers/Google Sheets).
/// Aceita `;` ou `,`, aspas, "R$ 1.234,56" ou "1234.56", e nomes de coluna variados.
public enum SpreadsheetImport {
    public enum Failure: Error, Equatable {
        case empty
        case missingColumns([String])
    }

    static let aliases: [String: [String]] = [
        "name": ["descricao", "nome", "despesa", "conta", "item", "despesas"],
        "amount": ["valor", "valor (r$)", "valor r$", "quanto", "preco", "previsto"],
        "category": ["categoria", "grupo", "tipo"],
        "day": ["dia", "vencimento", "venc", "venc.", "data", "dia do vencimento"],
        "variable": ["variavel", "varia", "valor variavel"],
    ]

    public static func bills(fromCSV text: String) throws -> [ImportedBill] {
        let rows = parse(text)
        guard let header = rows.first, rows.count > 1 else { throw Failure.empty }
        let keys = header.map(ReceiptParser.normalize).map { $0.trimmingCharacters(in: .whitespaces) }
        func column(_ field: String) -> Int? { keys.firstIndex { aliases[field]!.contains($0) } }

        guard let nameCol = column("name"), let amountCol = column("amount") else {
            var missing: [String] = []
            if column("name") == nil { missing.append("descrição") }
            if column("amount") == nil { missing.append("valor") }
            throw Failure.missingColumns(missing)
        }
        let categoryCol = column("category"), dayCol = column("day"), variableCol = column("variable")

        return rows.dropFirst().compactMap { row in
            func cell(_ i: Int?) -> String? {
                guard let i, i < row.count else { return nil }
                let v = row[i].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            guard let name = cell(nameCol), let amount = cell(amountCol).flatMap(money), amount.cents > 0 else { return nil }
            let flag = cell(variableCol).map(ReceiptParser.normalize) ?? ""
            return ImportedBill(name: name, amount: amount, categoryName: cell(categoryCol),
                                dueDay: cell(dayCol).flatMap(day) ?? 10,
                                isVariable: ["sim", "s", "x", "true", "1", "variavel"].contains(flag))
        }
    }

    /// "R$ 1.234,56" · "1234,56" · "1234.56" · "-96,40"
    static func money(_ s: String) -> Money? {
        var t = s.replacingOccurrences(of: "R$", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: "-", with: "")
        if let comma = t.lastIndex(of: ","), let dot = t.lastIndex(of: "."), dot > comma {
            // formato americano: 1,200.00 → 1200,00
            t = t.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: ",")
        } else if !t.contains(","), let dot = t.lastIndex(of: "."), t.distance(from: dot, to: t.endIndex) == 3 {
            t = t.replacingOccurrences(of: ".", with: ",")  // 1234.56 → 1234,56
        }
        return BRL.parse(t)
    }

    /// "5" · "05/09/2026" · "dia 12" → dia (1…28; 29–31 viram 28, como no app).
    static func day(_ s: String) -> Int? {
        let digits = s.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
        guard let d = digits, (1...31).contains(d) else { return nil }
        return min(d, 28)
    }

    /// CSV simples com aspas. Detecta `;` ou `,` pelo cabeçalho.
    static func parse(_ text: String) -> [[String]] {
        let clean = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let firstLine = clean.prefix { $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
        let sep: Character = firstLine.filter { $0 == ";" }.count >= firstLine.filter { $0 == "," }.count ? ";" : ","
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var it = clean.makeIterator()
        while let c = it.next() {
            if quoted {
                if c == "\"" {
                    // "" dentro de aspas é uma aspa literal
                    var look = it
                    if look.next() == "\"" { field.append("\""); it = look } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == sep {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
                row = []; field = ""
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }
}
