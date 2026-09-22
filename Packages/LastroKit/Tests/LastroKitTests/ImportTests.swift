import Foundation
import Testing
@testable import LastroKit

@Suite("Recibos: cupom e compartilhados")
struct ReceiptParserTests {
    @Test func cupomFiscalDePadaria() {
        let r = ReceiptParser.parse(lines: [
            "PADARIA REAL LTDA",
            "CNPJ 12.345.678/0001-90",
            "Rua das Flores, 123",
            "CUPOM FISCAL ELETRONICO - SAT",
            "1 PAO FRANCES KG 0,350 X 19,90 6,97",
            "2 CAFE COM LEITE 1 X 8,50 8,50",
            "3 PAO DE QUEIJO 2 X 4,15 8,30",
            "TOTAL R$ 23,80",
            "Cartao de Debito 23,80",
            "Valor aproximado dos tributos R$ 3,10",
        ])
        #expect(r.merchant == "Padaria Real")
        #expect(r.amount == Money(cents: 2_380))
        #expect(r.categorySlug == "rango")
        #expect(r.app == nil)
    }

    @Test func totalNaLinhaDeBaixo() {
        let r = ReceiptParser.parse(lines: ["SUPERMERCADO BOM PRECO", "ARROZ 5KG 24,90", "VALOR TOTAL R$", "31,39"])
        #expect(r.amount == Money(cents: 3_139))
        #expect(r.categorySlug == "mercado")
        #expect(r.merchant == "Supermercado Bom Preco")
    }

    @Test func ifoodCompartilhado() {
        let r = ReceiptParser.parse(text: """
        Seu pedido do McDonald's foi entregue!
        Subtotal R$ 38,90
        Taxa de entrega R$ 4,00
        Total R$ 42,90
        Pago com Nubank •••• 4821
        ifood.com.br
        """)
        #expect(r.app == "iFood" && r.merchant == "iFood")
        #expect(r.amount == Money(cents: 4_290))
        #expect(r.categorySlug == "rango")
    }

    @Test func uberCompartilhado() {
        let r = ReceiptParser.parse(text: "Obrigado por viajar com a Uber\nTotal R$27,60\nVisa ••1190")
        #expect(r.app == "Uber" && r.categorySlug == "transporte")
        #expect(r.amount == Money(cents: 2_760))
    }

    @Test func semTotalPegaOMaiorValor() {
        let r = ReceiptParser.parse(lines: ["Mercadinho Sao Jose", "Arroz 5kg 24,90", "Feijao 8,49"])
        #expect(r.amount == Money(cents: 2_490))
        #expect(r.categorySlug == "mercado")
    }

    @Test func valoresBrasileiros() {
        #expect(ReceiptParser.amounts(in: "1.234,56 e R$ 7,00 e 12,345") == [Money(cents: 123_456), Money(cents: 700)])
    }

    @Test func nomes() {
        #expect(ReceiptParser.prettyName("DROGARIA SAO PAULO S/A") == "Drogaria Sao Paulo")
        #expect(ReceiptParser.prettyName("CASA DE CARNES DO ZE ME") == "Casa de Carnes do Ze")
    }
}

@Suite("Planilha → contas fixas")
struct SpreadsheetImportTests {
    @Test func csvComPontoEVirgulaDoExcel() throws {
        let csv = """
        \u{FEFF}Descrição;Valor;Categoria;Vencimento;Variável
        Aluguel;R$ 3.200,00;Moradia;05;
        "Luz; enel";412,50;Moradia;10/09/2026;sim
        Dízimo;2310;Igreja & Ofertas;2;
        ;100,00;Moradia;3;
        Acordo Igor;1.000,00;;28;
        Academia;120,00;Saúde;31;
        """
        let bills = try SpreadsheetImport.bills(fromCSV: csv)
        #expect(bills.count == 5)  // linha sem nome é ignorada
        #expect(bills[0] == ImportedBill(name: "Aluguel", amount: Money(cents: 320_000), categoryName: "Moradia", dueDay: 5, isVariable: false))
        #expect(bills[1].name == "Luz; enel" && bills[1].dueDay == 10 && bills[1].isVariable)
        #expect(bills[2].amount == Money(cents: 231_000))
        #expect(bills[3].categoryName == nil)
        #expect(bills[4].dueDay == 28)  // 31 vira 28
    }

    @Test func csvComVirgulaDoGoogleSheets() throws {
        let csv = "Nome,Valor,Dia\r\nStreaming,39.90,27\r\n\"Mesada, Lorena\",\"1,200.00\",1\r\n"
        let bills = try SpreadsheetImport.bills(fromCSV: csv)
        #expect(bills.first == ImportedBill(name: "Streaming", amount: Money(cents: 3_990), categoryName: nil, dueDay: 27, isVariable: false))
        #expect(bills.count == 2)
        #expect(bills.last?.name == "Mesada, Lorena" && bills.last?.amount == Money(cents: 120_000))
        #expect(SpreadsheetImport.money("R$ 1.234,56") == Money(cents: 123_456))
        #expect(SpreadsheetImport.money("-96,40") == Money(cents: 9_640))
    }

    @Test func faltaColuna() {
        #expect(throws: SpreadsheetImport.Failure.missingColumns(["valor"])) {
            try SpreadsheetImport.bills(fromCSV: "Nome;Dia\nAluguel;5")
        }
        #expect(throws: SpreadsheetImport.Failure.empty) {
            try SpreadsheetImport.bills(fromCSV: "Nome;Valor")
        }
    }
}
