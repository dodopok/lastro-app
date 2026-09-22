import Foundation
import LastroKit

/// Tabelas sincronizadas. O nome é o da tabela no Postgres.
enum SyncTable: String, CaseIterable, Sendable {
    case profiles, categories, cards, cardCarryovers = "card_carryovers", bills, months
    case monthBudgets = "month_budgets", monthExtras = "month_extras", transactions, receipts, debts, goals, payments

    /// `payments` é escrita só pelo servidor.
    var isWritable: Bool { self != .payments }
    var conflictKey: String { self == .profiles ? "user_id" : "id" }
}

/// O que o app precisa do backend. `SupabaseRemote` implementa; testes usam um fake.
protocol Remote: Sendable {
    var userId: UUID? { get async }

    /// Linhas alteradas depois de `since` (inclui apagadas), como JSON array.
    func pull(_ table: SyncTable, since: Date?) async throws -> Data
    /// Upsert idempotente de um JSON array de linhas.
    func upsert(_ table: SyncTable, rows: Data) async throws
    func openMonth(_ month: YearMonth) async throws
    func seedDemo() async throws

    /// Piloto: pedir pagamento e aprovar depois do Face ID.
    func requestPayment(_ request: PaymentRequest) async throws -> Data
    func approvePayment(_ id: UUID) async throws -> Data
}

/// Corpo de POST /pagamentos (supabase/functions/pagamentos).
struct PaymentRequest: Encodable, Sendable {
    var tipo: String        // "pix" | "boleto"
    var valor: Int          // centavos
    var destino: String
    var data: String        // AAAA-MM-DD
    var exigeAprovacao: Bool
    var contaId: UUID?
    var lancamentoId: UUID?
    var chave: String       // idempotência
}
