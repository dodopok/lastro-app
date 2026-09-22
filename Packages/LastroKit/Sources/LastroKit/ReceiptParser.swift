import Foundation

/// Lê o texto de um cupom fiscal (OCR) ou de um recibo compartilhado (iFood,
/// Uber…) e tira dali o valor total, o estabelecimento e uma categoria sugerida.
public struct ParsedReceipt: Hashable, Sendable {
    public var merchant: String?
    public var amount: Money?
    /// Slug da categoria sugerida (`rango`, `mercado`…), se der pra adivinhar.
    public var categorySlug: String?
    /// App de origem, quando reconhecido ("iFood", "Uber").
    public var app: String?

    public init(merchant: String? = nil, amount: Money? = nil, categorySlug: String? = nil, app: String? = nil) {
        self.merchant = merchant
        self.amount = amount
        self.categorySlug = categorySlug
        self.app = app
    }
}

public enum ReceiptParser {
    /// Linhas de texto na ordem de leitura (de cima para baixo).
    public static func parse(lines raw: [String]) -> ParsedReceipt {
        let lines = raw.flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let all = normalize(lines.joined(separator: "\n"))
        let brand = brands.first { b in b.keys.contains { all.contains($0) } }
        return ParsedReceipt(
            merchant: brand?.name ?? merchant(in: lines),
            amount: total(in: lines),
            categorySlug: brand?.category ?? genericCategory(all),
            app: brand?.isApp == true ? brand?.name : nil)
    }

    public static func parse(text: String) -> ParsedReceipt { parse(lines: [text]) }

    // MARK: valor

    /// Prioridade: linhas com "total"/"valor a pagar"; senão, o maior valor do texto.
    static func total(in lines: [String]) -> Money? {
        let keywords = ["valor a pagar", "total a pagar", "valor pago", "total pago", "valor total", "total r$", "total:", "total"]
        let excluded = ["subtotal", "tribut", "imposto", "desconto", "troco", "itens", "qtd", "quantidade", "taxa de entrega"]
        let norm = lines.map(normalize)
        for kw in keywords {
            for (i, l) in norm.enumerated() where l.contains(kw) && !excluded.contains(where: { l.contains($0) }) {
                if let v = amounts(in: lines[i]).last { return v }
                if i + 1 < lines.count, let v = amounts(in: lines[i + 1]).first { return v }
            }
        }
        return zip(lines, norm)
            .filter { _, n in !excluded.contains(where: { n.contains($0) }) }
            .flatMap { l, _ in amounts(in: l) }
            .max()
    }

    /// Valores no formato brasileiro: "1.234,56", "42,90", "R$ 7,00".
    public static func amounts(in line: String) -> [Money] {
        let pattern = /(\d{1,3}(?:\.\d{3})+|\d+),(\d{2})(?!\d)/
        return line.matches(of: pattern).compactMap { m in
            BRL.parse("\(m.output.1),\(m.output.2)")
        }
    }

    // MARK: estabelecimento

    struct Brand: Sendable {
        let name: String
        let keys: [String]
        let category: String
        var isApp = false
    }

    static let brands: [Brand] = [
        Brand(name: "Uber Eats", keys: ["uber eats"], category: "rango", isApp: true),
        Brand(name: "iFood", keys: ["ifood"], category: "rango", isApp: true),
        Brand(name: "Rappi", keys: ["rappi"], category: "rango", isApp: true),
        Brand(name: "Uber", keys: ["uber"], category: "transporte", isApp: true),
        Brand(name: "99", keys: ["99app", "99pop", "99 pop", "corrida 99", "app 99"], category: "transporte", isApp: true),
        Brand(name: "Drogasil", keys: ["drogasil"], category: "saude"),
        Brand(name: "Droga Raia", keys: ["droga raia", "drogaraia"], category: "saude"),
        Brand(name: "Pague Menos", keys: ["pague menos"], category: "saude"),
        Brand(name: "Atacadão", keys: ["atacadao"], category: "mercado"),
        Brand(name: "Assaí", keys: ["assai atacadista", "assai"], category: "mercado"),
        Brand(name: "Carrefour", keys: ["carrefour"], category: "mercado"),
        Brand(name: "Pão de Açúcar", keys: ["pao de acucar"], category: "mercado"),
        Brand(name: "Shell", keys: ["shell"], category: "transporte"),
        Brand(name: "Ipiranga", keys: ["ipiranga"], category: "transporte"),
    ]

    static let genericKeywords: [(String, [String])] = [
        ("rango", ["padaria", "panificadora", "cafe", "cafeteria", "restaurante", "lanchonete", "pizzaria", "hamburgueria", "sorveteria", "confeitaria"]),
        ("mercado", ["supermercado", "minimercado", "mercadinho", "mercado", "hortifruti", "sacolao", "atacadista", "mercearia", "acougue"]),
        ("transporte", ["posto", "combustivel", "gasolina", "etanol", "estacionamento", "pedagio"]),
        ("saude", ["farmacia", "drogaria", "laboratorio", "clinica"]),
        ("lazer", ["cinema", "ingresso", "teatro", "livraria"]),
    ]

    static func genericCategory(_ normalized: String) -> String? {
        genericKeywords.first { _, keys in keys.contains { normalized.contains($0) } }?.0
    }

    /// Primeira linha com cara de nome: letras de verdade, sem CNPJ, endereço ou cabeçalho fiscal.
    static func merchant(in lines: [String]) -> String? {
        let skip = ["cnpj", "cpf", "cupom", "nfc", "nf-e", "documento", "danfe", "extrato", "consumidor", "sat ",
                    "rua ", "av ", "av.", "avenida", "endereco", "www", "http", "tel:", "tel ", "fone", "ie:", "im:", "data:", "hora:"]
        for line in lines.prefix(8) {
            let n = normalize(line)
            guard !skip.contains(where: { n.contains($0) }) else { continue }
            let letters = line.filter(\.isLetter).count
            guard letters >= 3, Double(letters) / Double(max(1, line.count)) > 0.6 else { continue }
            return prettyName(line)
        }
        return nil
    }

    /// "PADARIA REAL LTDA" → "Padaria Real"
    static func prettyName(_ s: String) -> String {
        var words = s.split(separator: " ").map(String.init)
        let suffixes: Set<String> = ["ltda", "ltda.", "me", "eireli", "s/a", "sa", "s.a.", "epp", "mei"]
        while let last = words.last, suffixes.contains(last.lowercased()) { words.removeLast() }
        let small: Set<String> = ["de", "da", "do", "das", "dos", "e"]
        return words.enumerated().map { i, w in
            let lower = w.lowercased(with: Locale(identifier: "pt_BR"))
            return i > 0 && small.contains(lower) ? lower : lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }
}
