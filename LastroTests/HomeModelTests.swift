import Foundation
import LastroKit
import Testing
@testable import Lastro

/// A Home tem que dizer exatamente o que o protótipo diz com os mesmos dados.
@MainActor
struct HomeModelTests {
    let ledger = DemoData.ledger()
    let today = (month: DemoData.current, day: DemoData.today)

    @Test func setembroCorrente() {
        let m = HomeModel(ledger: ledger, selected: DemoData.current, today: today)
        #expect(m.mode == .current)
        #expect(m.subtitle == "dia 21 · faltam 9 dias")
        #expect(m.heroes.map(\.label) == ["Sobra prevista", "Saldo confirmado agora", "Falta pagar das fixas"])
        #expect(m.heroes[2].sub == "6 contas até o dia 30")
        #expect(m.shortcuts.map(\.value) == ["R$ 72,26", "R$ 6.434"])
        #expect(m.pendingCount == 8)
        #expect(m.pending.count == 3)
        #expect(m.categoriesRight == "R$ 20.782 de R$ 21.402")
        #expect(m.receiptsCount == 3)
        #expect(m.miudezas?.title == "R$ 523,60 em 18 gastos pequenos")
        #expect(m.miudezas?.sub == "Tudo abaixo de R$ 50 em setembro. Mais que a conta de luz inteira.")
        #expect(m.rail.map(\.month.shortName) == ["JUL", "AGO", "SET", "OUT", "NOV", "DEZ"])
    }

    @Test func homeMostraSoAsCategoriasQuePedemAtencao() {
        let m = HomeModel(ledger: ledger, selected: DemoData.current, today: today)
        // Estouradas primeiro, depois as variáveis mais perto do limite; fixas no orçamento ficam de fora.
        #expect(m.focusCards.map(\.category.name) == ["Lazer & Assinaturas", "Saúde", "Mercado", "Transporte"])
        #expect(m.categoryCards.count == 11)
    }

    @Test func linhaDeAprovar() {
        let m = HomeModel(ledger: ledger, selected: DemoData.current, today: today)
        let matheus = m.pending.first { $0.entry.description == "Ajuda ao Matheus" }
        #expect(matheus?.tag?.text == "Aprovar")
        #expect(matheus?.meta == "hoje · Pix")
        let gas = m.pending.first { $0.entry.description == "Gás" }
        #expect(gas?.tag?.text == "estimado")
        #expect(gas?.value == "~R$ 96,40")
    }

    @Test func agostoFechado() {
        let m = HomeModel(ledger: ledger, selected: DemoData.current.previous, today: today)
        #expect(m.mode == .closed)
        #expect(m.heroes[0].value == Money(cents: -21_000))
        #expect(m.heroes[0].sub == "o mês fechou no vermelho")
        #expect(m.segments.map(\.label) == ["Saiu", "Faltou"])
        #expect(m.pending.isEmpty && m.miudezas == nil)
    }

    @Test func outubroPlanejamento() {
        let m = HomeModel(ledger: ledger, selected: DemoData.current.next, today: today)
        #expect(m.mode == .plan)
        #expect(m.heroes[1].sub == "18 contas nasceram sozinhas")
        #expect(m.pilotLine == "12 contas vão se pagar sozinhas")
        #expect(m.categoriesRight == "toque para ajustar")
    }

    @Test func tecladoESalvar() {
        let store = AppStore.preview()
        let before = store.ledger.entries.count
        let rango = store.ledger.activeCategories.first { $0.slug == "rango" }!
        store.addExpense(amount: Money(cents: 2_380), categoryId: rango.id, cardId: nil, description: "Padaria Real")
        #expect(store.ledger.entries.count == before + 1)
        #expect(store.toast?.message == "R$ 23,80 salvo em Rango & Café")
    }
}
