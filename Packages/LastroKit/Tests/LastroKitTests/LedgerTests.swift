import Foundation
import Testing
@testable import LastroKit

/// Os números esperados saíram de rodar a lógica do protótipo (Lastro.dc.html)
/// com os mesmos dados. Se algum mudar, o app deixou de bater com o design.
@Suite("Mês corrente = protótipo")
struct CurrentMonthTests {
    let m = CurrentMonth(DemoData.ledger(), month: DemoData.current, today: DemoData.today)

    @Test func sobraPrevista() { #expect(m.forecastLeftover == Money(cents: 159_587)) }
    @Test func saldoConfirmado() { #expect(m.confirmedBalance == Money(cents: 876_807)) }

    @Test func faltaPagarDasFixas() {
        #expect(m.pendingFixed.count == 6)
        #expect(m.pendingFixedTotal == Money(cents: 639_640))
    }

    @Test func podeGastarHoje() { #expect(m.canSpendToday == Money(cents: 7_226)) }

    @Test func faturas() {
        #expect(m.openStatements == Money(cents: 643_370))
        let nubank = m.ledger.activeCards.first { $0.name == "Nubank" }!
        #expect(m.statement(card: nubank.id) == Money(cents: 246_350))
    }

    @Test func miudezas() {
        #expect(m.smallSpends.count == 18)
        #expect(m.smallSpends.sum(\.amountCents) == Money(cents: 52_360))
    }

    @Test func pendentes() { #expect(m.pending.count == 8) }

    @Test func totaisDasCategorias() {
        #expect(m.totalSpent == Money(cents: 2_078_153))
        #expect(m.totalBudget == Money(cents: 2_140_233))
        let rango = m.categories.first { $0.category.slug == "rango" }!
        #expect(rango.spent == Money(cents: 34_690))
        #expect(rango.percent == 58)
    }

    @Test func aprovarAcimaDeMil() {
        let matheus = m.pending.first { $0.description == "Ajuda ao Matheus" }!
        let gas = m.pending.first { $0.description == "Gás" }!
        #expect(m.needsApproval(matheus))
        #expect(!m.needsApproval(gas))  // manual
    }

    @Test func proximoPiloto() { #expect(m.nextAutopay?.name == "Aula de canto") }
    @Test func acimaDaTrava() { #expect(m.isAboveSafetyFloor) }
}

@Suite struct ClosedAndPlannedTests {
    let ledger = DemoData.ledger()

    @Test func agostoFechouNoVermelho() {
        let aug = ClosedMonth(ledger, month: YearMonth(year: 2026, month: 8))
        #expect(aug.out == Money(cents: 2_115_533))
        #expect(aug.leftover == Money(cents: -21_000))
    }

    @Test func historicoDoAno() {
        let h = YearHistory(ledger, current: DemoData.current, today: DemoData.today)
        #expect(h.points.count == 9)
        #expect(h.points.last?.isForecast == true)
        #expect(h.points.map(\.leftover.cents).prefix(8) == [82_000, -34_000, 121_000, 41_000, -89_000, 15_000, 62_000, -21_000])
    }

    @Test func planejamentoDeOutubro() {
        let oct = PlannedMonth(ledger, month: DemoData.current.next)
        #expect(oct.total == Money(cents: 2_140_233))
        #expect(oct.leftover == Money(cents: 169_767))
        #expect(oct.savable == Money(cents: 118_837))
    }

    @Test func reservaEDividas() {
        #expect(ledger.billsTotal == Money(cents: 1_930_233))
        #expect(abs(ledger.emergencyMonths - 1.7977) < 0.001)
        #expect(ledger.openDebt == Money(cents: 6_696_000))
    }
}

@Suite struct MoneyTests {
    @Test func formato() {
        #expect(BRL.format(Money(cents: 1_234_560)) == "R$ 12.345,60")
        #expect(BRL.format(Money(cents: -50)) == "−R$ 0,50")
        #expect(BRL.format(.zero) == "R$ 0,00")
        #expect(BRL.rounded(Money(cents: 123_450)) == "R$ 1.235")
        #expect(BRL.rounded(Money(cents: -123_460)) == "−R$ 1.235")
        #expect(BRL.number(Money(cents: 2_140_233)) == "21.402")
    }

    @Test func heroi() {
        let p = BRL.heroParts(Money(cents: 159_587))
        #expect(p.sign == "" && p.integer == "1.595" && p.cents == ",87")
        #expect(BRL.heroParts(Money(cents: -21_005)).sign == "−")
    }

    @Test(arguments: [("412,50", 41_250), ("1.234,5", 123_450), ("96", 9_600), ("0,07", 7), (",5", 50)])
    func parse(text: String, cents: Int) {
        #expect(BRL.parse(text) == Money(cents: cents))
    }

    @Test func parseInvalido() {
        #expect(BRL.parse("1,2,3") == nil)
        #expect(BRL.parse("abc") == nil)
    }
}

@Suite struct AmountInputTests {
    @Test func digitaEFormata() {
        var a = AmountInput()
        for k: AmountInput.Key in [.digit(1), .digit(2), .digit(3), .digit(4), .comma, .digit(5)] { a.press(k) }
        #expect(a.display == "1.234,5")
        #expect(a.money == Money(cents: 123_450))
    }

    @Test func regras() {
        var a = AmountInput()
        #expect(a.press(.comma))
        #expect(a.raw == "0,")
        #expect(!a.press(.comma))
        a.press(.digit(9)); a.press(.digit(9))
        #expect(!a.press(.digit(1)))  // só 2 decimais
        var b = AmountInput()
        for _ in 0..<7 { b.press(.digit(9)) }
        #expect(!b.press(.digit(9)))  // até 7 dígitos
        var z = AmountInput()
        z.press(.digit(0)); z.press(.digit(5))
        #expect(z.raw == "5")  // zero à esquerda some
        z.press(.delete); z.press(.delete)
        #expect(z.isEmpty && !z.press(.delete))
    }

    @Test func aPartirDeValor() {
        #expect(AmountInput(Money(cents: 4_290)).raw == "42,90")
        #expect(AmountInput(Money(cents: 2_000)).raw == "20")
    }
}

@Suite struct YearMonthTests {
    @Test func basico() {
        let set = YearMonth(year: 2026, month: 9)
        #expect(set.iso == "2026-09-01")
        #expect(set.name == "Setembro" && set.shortName == "SET")
        #expect(set.numberOfDays == 30)
        #expect(YearMonth(year: 2026, month: 12).next == YearMonth(year: 2027, month: 1))
        #expect(set.adding(months: -9) == YearMonth(year: 2025, month: 12))
        #expect(YearMonth(iso: "2026-09-01") == set)
        #expect(YearMonth(year: 2028, month: 2).numberOfDays == 29)
    }
}

@Suite struct CodingTests {
    @Test func decodificaLinhaDoPostgrest() throws {
        let json = """
        {"id":"8b0c1a8e-2b1d-4c43-9e0a-6f1f7b3c2d10","month":"2026-09-01","day":21,"description":"iFood",
         "category_id":"CA7E0000-0000-0000-0000-000000000003","amount_cents":3650,"method":"cartao",
         "card_id":"CA4D0000-0000-0000-0000-000000000001","confirmed":false,"kind":"variavel","source":"manual",
         "bill_id":null,"estimated":false,"updated_at":"2026-09-22T19:35:03.103854+00:00","deleted_at":null}
        """
        let e = try LastroCoding.decoder.decode(Entry.self, from: Data(json.utf8))
        #expect(e.amountCents == Money(cents: 3_650))
        #expect(e.month == DemoData.current)
        #expect(e.method == .cartao && e.cardId != nil)
        #expect(e.updatedAt != nil)

        let back = try LastroCoding.encoder.encode(e)
        let obj = try JSONSerialization.jsonObject(with: back) as! [String: Any]
        #expect(obj["amount_cents"] as? Int == 3_650)
        #expect(obj["month"] as? String == "2026-09-01")
    }
}

@Suite struct OKLCHTests {
    // Referência: culori 4 (oklch → p3)
    @Test(arguments: [
        (0.55, 0.21, 262.0, 0.2139, 0.3941, 0.8829),
        (0.56, 0.14, 155.0, 0.2338, 0.5384, 0.3289),
        (0.57, 0.20, 25.0, 0.7640, 0.2467, 0.2345),
    ])
    func displayP3(l: Double, c: Double, h: Double, r: Double, g: Double, b: Double) {
        let p = OKLCH(l, c, h).displayP3
        #expect(abs(p.r - r) < 0.002 && abs(p.g - g) < 0.002 && abs(p.b - b) < 0.002)
    }

    @Test func foraDaGamaERecortado() {
        let p = Palette.category(75).displayP3
        #expect(p.b == 0)
    }
}
