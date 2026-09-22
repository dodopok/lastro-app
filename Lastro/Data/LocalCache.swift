import Foundation
import LastroKit
import SwiftData

// Cache offline-first. Uma linha por registro do servidor, guardada como o
// próprio JSON do PostgREST: o schema do app não precisa espelhar o banco
// tabela por tabela, e migrar o banco não quebra o cache.

@Model
final class CachedRow {
    #Unique<CachedRow>([\.key])
    var key: String  // "transactions:<uuid>"
    var table: String
    var json: Data

    init(key: String, table: String, json: Data) {
        self.key = key
        self.table = table
        self.json = json
    }
}

/// Mudança local ainda não enviada (outbox). Só a última de cada registro fica.
@Model
final class PendingChange {
    #Unique<PendingChange>([\.key])
    var key: String
    var table: String
    var json: Data
    var createdAt: Date

    init(key: String, table: String, json: Data, createdAt: Date = .now) {
        self.key = key
        self.table = table
        self.json = json
        self.createdAt = createdAt
    }
}

@Model
final class SyncCursor {
    #Unique<SyncCursor>([\.table])
    var table: String
    var updatedAt: Date

    init(table: String, updatedAt: Date) {
        self.table = table
        self.updatedAt = updatedAt
    }
}

struct PendingSnapshot: Sendable {
    let key: String
    let table: SyncTable
    let json: Data
}

@ModelActor
actor LocalCache {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration("Lastro", isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: CachedRow.self, PendingChange.self, SyncCursor.self, configurations: config)
    }

    static func key(_ table: SyncTable, _ id: String) -> String { "\(table.rawValue):\(id.lowercased())" }

    func rows(_ table: SyncTable) throws -> [Data] {
        let name = table.rawValue
        return try modelContext.fetch(FetchDescriptor<CachedRow>(predicate: #Predicate { $0.table == name })).map(\.json)
    }

    /// Grava o que veio do servidor. Registros com mudança local pendente não são sobrescritos.
    func store(_ table: SyncTable, rows: [(id: String, json: Data)]) throws {
        let pendingKeys = Set(try modelContext.fetch(FetchDescriptor<PendingChange>()).map(\.key))
        for row in rows {
            let key = Self.key(table, row.id)
            guard !pendingKeys.contains(key) else { continue }
            upsertRow(key: key, table: table, json: row.json)
        }
        try modelContext.save()
    }

    /// Mudança feita no aparelho: vale na hora (cache) e entra na fila de envio.
    func enqueue(_ table: SyncTable, id: String, json: Data) throws {
        let key = Self.key(table, id)
        upsertRow(key: key, table: table, json: json)
        let existing = try modelContext.fetch(FetchDescriptor<PendingChange>(predicate: #Predicate { $0.key == key }))
        if let p = existing.first {
            p.json = json
            p.createdAt = .now
        } else {
            modelContext.insert(PendingChange(key: key, table: table.rawValue, json: json))
        }
        try modelContext.save()
    }

    func pending() throws -> [PendingSnapshot] {
        try modelContext.fetch(FetchDescriptor<PendingChange>(sortBy: [SortDescriptor(\.createdAt)]))
            .compactMap { p in SyncTable(rawValue: p.table).map { PendingSnapshot(key: p.key, table: $0, json: p.json) } }
    }

    /// Remove da fila o que foi enviado, desde que não tenha mudado de novo no meio tempo.
    func markSent(_ sent: [PendingSnapshot]) throws {
        for s in sent {
            let key = s.key
            let found = try modelContext.fetch(FetchDescriptor<PendingChange>(predicate: #Predicate { $0.key == key }))
            for p in found where p.json == s.json { modelContext.delete(p) }
        }
        try modelContext.save()
    }

    func cursor(_ table: SyncTable) throws -> Date? {
        let name = table.rawValue
        return try modelContext.fetch(FetchDescriptor<SyncCursor>(predicate: #Predicate { $0.table == name })).first?.updatedAt
    }

    func setCursor(_ table: SyncTable, _ date: Date) throws {
        let name = table.rawValue
        if let c = try modelContext.fetch(FetchDescriptor<SyncCursor>(predicate: #Predicate { $0.table == name })).first {
            c.updatedAt = max(c.updatedAt, date)
        } else {
            modelContext.insert(SyncCursor(table: name, updatedAt: date))
        }
        try modelContext.save()
    }

    func reset() throws {
        try modelContext.delete(model: CachedRow.self)
        try modelContext.delete(model: PendingChange.self)
        try modelContext.delete(model: SyncCursor.self)
        try modelContext.save()
    }

    private func upsertRow(key: String, table: SyncTable, json: Data) {
        let existing = try? modelContext.fetch(FetchDescriptor<CachedRow>(predicate: #Predicate { $0.key == key }))
        if let row = existing?.first {
            row.json = json
        } else {
            modelContext.insert(CachedRow(key: key, table: table.rawValue, json: json))
        }
    }
}
