import Foundation
import LastroKit

/// Caixa de entrada entre a extensão de compartilhar e o app. A extensão não
/// tem o cache nem a sessão do app: ela só grava o recibo aqui (App Group), e
/// o app transforma em `Receipt` quando volta a ficar ativo.
enum ReceiptInbox {
    static let appGroup = "group.app.lastro"

    struct Item: Codable, Sendable, Identifiable {
        var id = UUID()
        var merchant: String
        var amountCents: Int
        var categorySlug: String?
        var originLabel: String
        var source: String      // "share" | "scan"
        var capturedAt = Date()
    }

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("recibos-pendentes.json")
    }

    static func append(_ item: Item) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        var items = read()
        items.append(item)
        try JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    static func read() -> [Item] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    /// Lê e esvazia. O app chama ao abrir e ao voltar para o primeiro plano.
    static func drain() -> [Item] {
        let items = read()
        if !items.isEmpty, let url { try? FileManager.default.removeItem(at: url) }
        return items
    }

    /// "Compartilhado do iFood · 20:14"
    static func originLabel(app: String?, source: String, date: Date = .now) -> String {
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if source == "scan" { return "Cupom escaneado · \(time)" }
        return app.map { "Compartilhado do \($0) · \(time)" } ?? "Compartilhado · \(time)"
    }
}
