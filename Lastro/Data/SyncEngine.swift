import Foundation
import LastroKit

/// Envia a fila local e puxa o que mudou no servidor. Estratégia:
///   1. push: upsert idempotente (ids são gerados no aparelho).
///   2. pull: por tabela, `updated_at > cursor − 5s` (a sobreposição cobre
///      transações que commitaram fora de ordem), paginado de 1000 em 1000.
///   3. registros com mudança local pendente não são sobrescritos pelo pull.
/// Conflito: última escrita vence, com o relógio do servidor.
actor SyncEngine {
    let remote: any Remote
    let cache: LocalCache
    private static let overlap: TimeInterval = 5

    init(remote: any Remote, cache: LocalCache) {
        self.remote = remote
        self.cache = cache
    }

    // MARK: escrita local

    func save<T: Encodable & Sendable>(_ table: SyncTable, id: UUID, _ value: T) async throws {
        precondition(table.isWritable)
        try await cache.enqueue(table, id: id.uuidString, json: LastroCoding.encoder.encode(value))
    }

    // MARK: sync

    func sync() async throws {
        try await push()
        try await pull()
    }

    func push() async throws {
        let pending = try await cache.pending()
        guard !pending.isEmpty else { return }
        // Ordem das tabelas respeita as chaves estrangeiras (categorias antes de lançamentos…).
        for table in SyncTable.allCases where table.isWritable {
            let batch = pending.filter { $0.table == table }
            guard !batch.isEmpty else { continue }
            var array = Data("[".utf8)
            for (i, p) in batch.enumerated() {
                if i > 0 { array.append(Data(",".utf8)) }
                array.append(p.json)
            }
            array.append(Data("]".utf8))
            try await remote.upsert(table, rows: array)
            try await cache.markSent(batch)
        }
    }

    func pull() async throws {
        for table in SyncTable.allCases {
            var since = try await cache.cursor(table).map { $0.addingTimeInterval(-Self.overlap) }
            while true {
                let data = try await remote.pull(table, since: since)
                let rows = try Self.split(data, table: table)
                try await cache.store(table, rows: rows.map { (id: $0.id, json: $0.json) })
                guard let last = rows.compactMap(\.updatedAt).max() else { break }
                try await cache.setCursor(table, last)
                if rows.count < 1000 { break }
                since = last
            }
        }
    }

    // MARK: leitura

    /// Monta o Ledger a partir do cache. `nil` se ainda não há perfil (primeiro login).
    func loadLedger() async throws -> Ledger? {
        func rows<T: Decodable>(_ table: SyncTable, as _: T.Type) async throws -> [T] {
            try await cache.rows(table).map { try LastroCoding.decoder.decode(T.self, from: $0) }
        }
        guard let profile = try await rows(.profiles, as: Profile.self).first else { return nil }
        return Ledger(
            profile: profile,
            categories: try await rows(.categories, as: BudgetCategory.self),
            cards: try await rows(.cards, as: Card.self),
            carryovers: try await rows(.cardCarryovers, as: CardCarryover.self),
            bills: try await rows(.bills, as: Bill.self),
            months: try await rows(.months, as: Month.self),
            budgets: try await rows(.monthBudgets, as: MonthBudget.self),
            extras: try await rows(.monthExtras, as: MonthExtra.self),
            entries: try await rows(.transactions, as: Entry.self),
            receipts: try await rows(.receipts, as: Receipt.self),
            debts: try await rows(.debts, as: Debt.self),
            goals: try await rows(.goals, as: Goal.self))
    }

    func payments() async throws -> [Payment] {
        try await cache.rows(.payments).map { try LastroCoding.decoder.decode(Payment.self, from: $0) }
    }

    // MARK: util

    struct Row: Sendable {
        let id: String
        let json: Data
        let updatedAt: Date?
    }

    /// Separa o array do PostgREST em linhas (id + JSON + updated_at).
    static func split(_ data: Data, table: SyncTable) throws -> [Row] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return try array.compactMap { obj in
            guard let id = obj[table.conflictKey] as? String else { return nil }
            let updated = (obj["updated_at"] as? String).flatMap(LastroCoding.parseTimestamp)
            return Row(id: id, json: try JSONSerialization.data(withJSONObject: obj), updatedAt: updated)
        }
    }
}
