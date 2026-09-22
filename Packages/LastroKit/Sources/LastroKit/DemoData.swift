import Foundation

/// Os dados do protótipo, em memória: previews, testes e modo demo sem rede.
/// Espelha `supabase/migrations/20260922000002_demo_seed.sql`.
public enum DemoData {
    public static let today = 21
    public static let current = YearMonth(year: 2026, month: 9)
    public static let userId = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!

    /// Sobra de jan–ago, em reais.
    static let history: [Double] = [820, -340, 1210, 410, -890, 150, 620, -210]

    public static func ledger() -> Ledger {
        let profile = Profile(userId: userId, monthlyIncomeCents: Money(reais: 23_100))

        let cats: [(String, String, Double, CategoryNature, Double, String)] = [
            ("moradia", "Moradia", 265, .fixo, 4522.33, "house"),
            ("mercado", "Mercado", 160, .variavel, 800, "cart"),
            ("rango", "Rango & Café", 75, .variavel, 600, "cup.and.saucer"),
            ("transporte", "Transporte", 225, .variavel, 400, "car"),
            ("saude", "Saúde", 20, .fixo, 1200, "heart"),
            ("mesadas", "Mesadas", 320, .fixo, 1700, "gift"),
            ("igreja", "Igreja & Ofertas", 290, .fixo, 3200, "hands.and.sparkles"),
            ("familia", "Família", 195, .fixo, 2090, "person.2"),
            ("lazer", "Lazer & Assinaturas", 345, .fixo, 480, "music.note"),
            ("dividas", "Dívidas", 45, .parcelado, 6110, "doc.plaintext"),
            ("imprevistos", "Imprevistos", 120, .reserva, 300, "umbrella"),
        ]
        let categories = cats.enumerated().map { i, c in
            BudgetCategory(id: stableID("cat", i), slug: c.0, name: c.1, hue: c.2, nature: c.3,
                     defaultBudgetCents: Money(reais: c.4), symbol: c.5, position: i)
        }
        let cat = Dictionary(uniqueKeysWithValues: categories.map { ($0.slug, $0.id) })

        let cardRows: [(String, String, String, Double, Double, Int, Int, Double)] = [
            ("nubank", "Nubank", "final 4821", 305, 14000, 28, 5, 2140.6),
            ("click", "Itaú Click", "final 1190", 48, 12000, 15, 22, 860.2),
            ("uniclass", "Itaú Uniclass", "final 7733", 258, 20000, 15, 22, 1420),
            ("lorena", "Itaú Lorena", "adicional · 7734", 350, 4000, 15, 22, 380.5),
            ("bradesco", "Bradesco", "final 0562", 22, 9000, 20, 28, 540),
            ("atacadao", "Atacadão", "final 3308", 150, 3000, 25, 2, 0),
        ]
        let cards = cardRows.enumerated().map { i, c in
            Card(id: stableID("card", i), name: c.1, subtitle: c.2, hue: c.3, limitCents: Money(reais: c.4),
                 closingDay: c.5, dueDay: c.6, position: i)
        }
        let card = Dictionary(uniqueKeysWithValues: zip(cardRows.map(\.0), cards.map(\.id)))
        let carryovers = zip(cardRows, cards).compactMap { row, c in
            row.7 > 0 ? CardCarryover(cardId: c.id, month: current, amountCents: Money(reais: row.7)) : nil
        }

        let billRows: [(String, String, String, Int, Double, Bool, Bool, PayMethod, String?)] = [
            ("aluguel", "Aluguel", "moradia", 5, 3200, false, true, .pix, "aluguel@imobsol.com.br"),
            ("condominio", "Condomínio", "moradia", 8, 455.43, false, false, .boleto, nil),
            ("luz", "Luz", "moradia", 10, 412.5, true, true, .boleto, nil),
            ("agua", "Água", "moradia", 12, 138.2, true, true, .boleto, nil),
            ("gas", "Gás", "moradia", 15, 96.4, true, false, .boleto, nil),
            ("net", "Internet e telefone", "moradia", 18, 219.8, false, true, .debito, nil),
            ("terapia", "Terapia", "saude", 7, 800, false, false, .pix, "clinica.alma@pix.com"),
            ("medicacao", "Medicação", "saude", 10, 400, false, false, .debito, nil),
            ("mes_lorena", "Mesada da Lorena", "mesadas", 1, 1200, false, true, .pix, "lorena@email.com"),
            ("mes_minha", "Minha mesada", "mesadas", 1, 500, false, true, .pix, nil),
            ("dizimo", "Dízimo", "igreja", 2, 2310, false, true, .pix, "igreja@pix.org.br"),
            ("ofertas", "Ofertas", "igreja", 14, 890, false, false, .pix, nil),
            ("matheus", "Ajuda ao Matheus", "familia", 21, 2090, false, true, .pix, "matheus.s@email.com"),
            ("canto", "Aula de canto", "lazer", 22, 360, false, true, .pix, nil),
            ("streaming", "Streaming", "lazer", 27, 120, false, true, .debito, nil),
            ("carro", "Parcela do carro", "dividas", 20, 2380, false, true, .boleto, nil),
            ("nubank_acordo", "Acordo Nubank", "dividas", 25, 2730, false, true, .boleto, nil),
            ("igor", "Acordo Igor", "dividas", 28, 1000, false, false, .pix, nil),
        ]
        let bills = billRows.enumerated().map { i, b in
            Bill(id: stableID("bill", i), name: b.1, categoryId: cat[b.2]!, dueDay: b.3, amountCents: Money(reais: b.4),
                 isVariable: b.5, autopay: b.6, method: b.7, pixKey: b.8)
        }
        let bill = Dictionary(uniqueKeysWithValues: zip(billRows.map(\.0), bills.map(\.id)))

        var months: [Month] = []
        var budgets: [MonthBudget] = []
        var entries: [Entry] = []

        // jan–ago: fechados, um lançamento consolidado por categoria
        for mi in 0..<8 {
            let m = YearMonth(year: 2026, month: mi + 1)
            var out = Money.zero
            for c in categories {
                let spent = c.nature.isFlexible
                    ? c.defaultBudgetCents.scaled(by: Double(72 + (c.position * 37 + mi * 53) % 48) / 100)
                    : c.defaultBudgetCents
                out += spent
                budgets.append(MonthBudget(month: m, categoryId: c.id, amountCents: c.defaultBudgetCents))
                entries.append(Entry(month: m, day: 28, description: "Consolidado da planilha", categoryId: c.id,
                                     amountCents: spent, method: .pix, confirmed: true,
                                     kind: kind(for: c.nature), source: .import))
            }
            months.append(Month(month: m, status: .closed, incomeCents: out + Money(reais: history[mi])))
        }

        // set: corrente · out–dez: planejamento
        for (m, status) in [(current, MonthStatus.open), (current.adding(months: 1), .planning),
                            (current.adding(months: 2), .planning), (current.adding(months: 3), .planning)] {
            months.append(Month(month: m, status: status, incomeCents: profile.monthlyIncomeCents))
            budgets += categories.map { MonthBudget(month: m, categoryId: $0.id, amountCents: $0.defaultBudgetCents) }
            for b in bills {
                let isCurrent = m == current
                let confirmed = isCurrent && b.dueDay <= today && b.id != bill["gas"] && b.id != bill["matheus"]
                let nature = categories.first { $0.id == b.categoryId }!.nature
                entries.append(Entry(month: m, day: b.dueDay, description: b.name, categoryId: b.categoryId,
                                     amountCents: b.amountCents, method: b.method, confirmed: confirmed,
                                     kind: nature == .parcelado ? .parcela : .fixa, source: .bill, billId: b.id,
                                     estimated: isCurrent ? b.id == bill["gas"] : b.isVariable))
            }
        }

        let variable: [(String, String, Int, Double, PayMethod, String?, Bool)] = [
            ("Atacadão", "mercado", 6, 312.4, .cartao, "atacadao", true),
            ("Pão de Açúcar", "mercado", 14, 186.9, .cartao, "click", true),
            ("Hortifruti", "mercado", 18, 48.7, .pix, nil, true),
            ("Mercadinho", "mercado", 20, 92.3, .debito, nil, true),
            ("iFood", "rango", 3, 38.9, .cartao, "nubank", true),
            ("Padaria", "rango", 5, 14.5, .debito, nil, true),
            ("Café", "rango", 6, 12, .debito, nil, true),
            ("iFood", "rango", 9, 46.8, .cartao, "nubank", true),
            ("Padaria", "rango", 11, 22.4, .pix, nil, true),
            ("iFood", "rango", 13, 41.9, .cartao, "nubank", true),
            ("Café", "rango", 16, 9.5, .debito, nil, true),
            ("iFood", "rango", 17, 49.9, .cartao, "nubank", true),
            ("Padaria", "rango", 19, 18.6, .pix, nil, true),
            ("iFood", "rango", 20, 44.9, .cartao, "nubank", true),
            ("Café", "rango", 21, 11, .debito, nil, true),
            ("iFood", "rango", 21, 36.5, .cartao, "nubank", false),
            ("Uber", "transporte", 4, 23.4, .cartao, "uniclass", true),
            ("Gasolina", "transporte", 8, 180, .cartao, "bradesco", true),
            ("Uber", "transporte", 15, 31.2, .cartao, "uniclass", true),
            ("Uber", "transporte", 19, 18.9, .cartao, "uniclass", true),
            ("99", "transporte", 21, 16.7, .cartao, "uniclass", false),
            ("Chaveiro", "imprevistos", 12, 120, .pix, nil, true),
            ("Cinema", "lazer", 13, 64, .cartao, "nubank", true),
            ("Farmácia", "saude", 16, 37.8, .pix, nil, true),
        ]
        for v in variable {
            entries.append(Entry(month: current, day: v.2, description: v.0, categoryId: cat[v.1]!,
                                 amountCents: Money(reais: v.3), method: v.4, cardId: v.5.flatMap { card[$0] },
                                 confirmed: v.6))
        }

        let debts = [
            Debt(name: "Carro", description: "financiamento", billId: bill["carro"], installmentCents: Money(reais: 2380),
                 installmentsTotal: 48, installmentsPaid: 23, paidCents: Money(reais: 2380 * 23), position: 0),
            Debt(name: "Nubank", description: "rotativo renegociado", billId: bill["nubank_acordo"],
                 installmentCents: Money(reais: 2730), installmentsTotal: 3, installmentsPaid: 1,
                 paidCents: Money(reais: 2730), position: 1),
            Debt(name: "Igor", description: "acordo", billId: bill["igor"], installmentCents: Money(reais: 1000),
                 installmentsTotal: 4, installmentsPaid: 2, paidCents: Money(reais: 2000), position: 2),
            Debt(name: "C&A", description: "quitado em julho", installmentCents: .zero, installmentsTotal: 6,
                 installmentsPaid: 6, paidCents: Money(reais: 1140), position: 3),
        ]

        let goals = [
            Goal(kind: .emergency, name: "Reserva de emergência", description: "6 meses de custo fixo",
                 targetCents: nil, savedCents: Money(reais: 34_700), hue: 155, position: 0),
            Goal(kind: .custom, name: "Quitar o Nubank", description: "2 parcelas restantes",
                 targetCents: Money(reais: 8190), savedCents: Money(reais: 2730), hue: 262, position: 1),
            Goal(kind: .custom, name: "Viagem de julho", description: "R$ 400 por mês",
                 targetCents: Money(reais: 8000), savedCents: Money(reais: 2400), hue: 55, position: 2),
        ]

        let now = Date(timeIntervalSince1970: 1_790_032_440)  // 2026-09-21 20:14 BRT
        let receipts = [
            Receipt(merchant: "iFood", originLabel: "Compartilhado do iFood · 20:14", source: .share,
                    amountCents: Money(reais: 42.9), categoryId: cat["rango"], cardId: card["nubank"], capturedAt: now),
            Receipt(merchant: "Uber", originLabel: "Compartilhado do Uber · 18:02", source: .share,
                    amountCents: Money(reais: 27.6), categoryId: cat["transporte"], cardId: card["uniclass"],
                    capturedAt: now.addingTimeInterval(-7_920)),
            Receipt(merchant: "Drogasil", originLabel: "Cupom escaneado · ontem", source: .scan,
                    amountCents: Money(reais: 64.3), categoryId: cat["saude"], cardId: nil,
                    capturedAt: now.addingTimeInterval(-86_400)),
        ]

        return Ledger(profile: profile, categories: categories, cards: cards, carryovers: carryovers, bills: bills,
                      months: months, budgets: budgets, entries: entries, receipts: receipts, debts: debts, goals: goals)
    }

    static func kind(for n: CategoryNature) -> TxKind {
        switch n {
        case .variavel, .reserva: .variavel
        case .parcelado: .parcela
        case .fixo: .fixa
        }
    }

    /// IDs estáveis para previews (a mesma categoria tem o mesmo id entre execuções).
    static func stableID(_ kind: String, _ i: Int) -> UUID {
        let prefix: String = switch kind {
        case "cat": "CA7E0000"
        case "card": "CA4D0000"
        default: "B1110000"
        }
        let tail = String(i + 1)
        return UUID(uuidString: "\(prefix)-0000-0000-0000-\(String(repeating: "0", count: 12 - tail.count))\(tail)")!
    }
}
