import Foundation
import LastroKit
import Supabase

/// Configuração lida do Info.plist (preenchido pelos xcconfig).
enum AppConfig {
    static var supabaseURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String).flatMap(URL.init(string:))
    }
    static var supabaseKey: String? {
        (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    /// Modo demo: dados do protótipo em memória, sem login e sem rede.
    static var isDemo: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "LASTRO_DEMO") as? String)?.uppercased() == "YES"
            || supabaseKey == nil
    }
}

final class SupabaseRemote: Remote {
    let client: SupabaseClient

    init(url: URL, key: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    var userId: UUID? {
        get async { client.auth.currentUser?.id }
    }

    func pull(_ table: SyncTable, since: Date?) async throws -> Data {
        var query = client.from(table.rawValue).select()
        if let since {
            query = query.gt("updated_at", value: since.ISO8601Format(.init(includingFractionalSeconds: true)))
        }
        return try await query.order("updated_at").limit(1000).execute().data
    }

    func upsert(_ table: SyncTable, rows: Data) async throws {
        let json = try JSONDecoder().decode([AnyJSON].self, from: rows)
        guard !json.isEmpty else { return }
        _ = try await client.from(table.rawValue).upsert(json, onConflict: table.conflictKey).execute()
    }

    func openMonth(_ month: YearMonth) async throws {
        _ = try await client.rpc("open_month", params: ["p_month": month.iso]).execute()
    }

    func seedDemo() async throws {
        _ = try await client.rpc("seed_demo").execute()
    }

    func requestPayment(_ request: PaymentRequest) async throws -> Data {
        try await invoke("pagamentos", body: request)
    }

    func approvePayment(_ id: UUID) async throws -> Data {
        try await invoke("pagamentos/\(id.uuidString.lowercased())/aprovar", body: [String: String]())
    }

    func pluggy(_ method: String, _ path: String, body: [String: String]) async throws -> Data {
        let m: FunctionInvokeOptions.Method = method == "DELETE" ? .delete : .post
        return try await client.functions.invoke("pluggy/\(path)", options: FunctionInvokeOptions(method: m, body: body)) { data, _ in
            data
        }
    }

    private func invoke(_ name: String, body: some Encodable & Sendable) async throws -> Data {
        try await client.functions.invoke(name, options: FunctionInvokeOptions(method: .post, body: body)) { data, _ in
            data
        }
    }

    // MARK: login

    func signInWithApple(idToken: String, nonce: String) async throws {
        _ = try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
