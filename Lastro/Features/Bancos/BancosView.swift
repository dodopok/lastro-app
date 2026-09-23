import LastroKit
import SwiftUI
import WebKit

/// Open Finance: bancos conectados pela Pluggy.
struct BancosView: View {
    @Environment(AppStore.self) private var store
    @State private var connect: ConnectSession?
    @State private var loadingToken = false
    @State private var toRemove: BankConnection?
    @State private var adopting = false
    @State private var itemId = ""

    struct ConnectSession: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        Screen(title: "Bancos", subtitle: "Open Finance · via Pluggy") {
            Callout(symbol: "building.columns", eyebrow: "Como funciona",
                    text: "O banco manda os gastos pra cá. O que você já tinha lançado ganha o selo de conferido; o que faltava entra sozinho, já com categoria. Pagamento de fatura e transferência entre suas contas ficam de fora, pra nada contar duas vezes.")

            if store.isDemo {
                Callout(symbol: "exclamationmark.circle",
                        text: "No modo demo não tem servidor. Configure o Supabase (Config/Secrets.xcconfig) para conectar um banco de verdade.",
                        tint: Color(OKLCHColor.amberSoft), iconColor: Color(OKLCHColor.amberText))
            }

            if !store.bankConnections.isEmpty {
                SectionHeader(title: "Conectados")
                PanelList(data: store.bankConnections) { c in
                    ConnectionRow(connection: c) { reconnect(c) } remove: { toRemove = c }
                }
                Button { Task { await store.syncBanks() } } label: {
                    HStack(spacing: 8) {
                        if store.isSyncingBanks { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                        Text(store.isSyncingBanks ? "Buscando no banco…" : "Sincronizar agora")
                    }
                    .textStyle(15, .semibold).foregroundStyle(.ink)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(.white.opacity(0.6), in: .capsule)
                    .overlay { Capsule().strokeBorder(.ink.opacity(0.08), lineWidth: 1) }
                    .contentShape(.capsule)
                }
                .buttonStyle(PressScale())
                .disabled(store.isSyncingBanks)
            }

            PrimaryButton(title: loadingToken ? "Abrindo…" : store.bankConnections.isEmpty ? "Conectar banco" : "Conectar outro banco",
                          enabled: !store.isDemo && !loadingToken) {
                open(itemId: nil)
            }

            Button("Já conectei no painel da Pluggy") { itemId = ""; adopting = true }
                .textStyle(14, .semibold).foregroundStyle(.ink.opacity(0.6))
                .frame(maxWidth: .infinity).frame(height: 40).contentShape(.rect)
                .buttonStyle(.plain)
                .disabled(store.isDemo || store.isSyncingBanks)

            Text("A Pluggy é autorizada pelo Banco Central. O Lastro só lê: nunca vê sua senha nem move dinheiro por aqui.")
                .textStyle(12.5).foregroundStyle(.ink.opacity(0.45))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.horizontal, 12)
        }
        .sheet(item: $connect) { session in
            PluggyConnectSheet(url: session.url) { itemId in
                connect = nil
                Task { await store.connectBank(itemId: itemId) }
            } onError: { message in
                connect = nil
                store.show(message)
            }
        }
        .confirmationDialog("Desconectar \(toRemove?.connectorName ?? "")?", isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }),
                            titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) {
                if let c = toRemove { Task { await store.disconnect(c) } }
            }
        } message: {
            Text("Os lançamentos que já vieram ficam. Novos gastos desse banco param de chegar.")
        }
        .alert("Usar conexão da Pluggy", isPresented: $adopting) {
            TextField("ID do item", text: $itemId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancelar", role: .cancel) {}
            Button("Conectar") {
                let id = itemId.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await store.connectBank(itemId: id) }
            }
        } message: {
            Text("No painel da Pluggy, abra o item da conexão e copie o ID dele. O Lastro passa a receber os gastos desse banco.")
        }
        .task { if !store.isDemo { await store.refresh() } }
    }

    private func reconnect(_ c: BankConnection) { open(itemId: c.pluggyItemId) }

    private func open(itemId: String?) {
        loadingToken = true
        Task {
            defer { loadingToken = false }
            do {
                let token = try await store.pluggyToken(itemId: itemId)
                var components = URLComponents(string: "https://connect.pluggy.ai")!
                components.queryItems = [
                    URLQueryItem(name: "connect_token", value: token.connectToken),
                    URLQueryItem(name: "with_sandbox", value: token.sandbox ? "true" : "false"),
                ]
                if let url = components.url { connect = ConnectSession(url: url) }
            } catch {
                store.show((error as? LocalizedError)?.errorDescription ?? "Não deu para abrir a Pluggy agora")
            }
        }
    }
}

struct ConnectionRow: View {
    let connection: BankConnection
    let reconnect: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: connection.connectorLogo.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "building.columns").font(.system(size: 16, weight: .medium)).foregroundStyle(.ink)
            }
            .frame(width: 26, height: 26)
            .frame(width: 38, height: 38)
            .background(.white, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.ink.opacity(0.06)) }

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.connectorName).textStyle(15, .semibold).foregroundStyle(.ink)
                HStack(spacing: 6) {
                    Tag(text: connection.statusLabel,
                        color: connection.needsAttention ? .warning : .positive,
                        background: (connection.needsAttention ? Color(Palette.amber) : Color(Palette.green)).opacity(0.14))
                    if let at = connection.lastSyncedAt {
                        Text(at.formatted(.relative(presentation: .named)))
                            .textStyle(12).foregroundStyle(.inkTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Reconectar", systemImage: "key") { reconnect() }
                Button("Desconectar", systemImage: "xmark.circle", role: .destructive) { remove() }
            } label: {
                Image(systemName: connection.needsAttention ? "exclamationmark.circle.fill" : "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(connection.needsAttention ? Color.warning : Color.ink.opacity(0.5))
                    .frame(width: 36, height: 36).contentShape(.rect)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

/// Widget oficial da Pluggy numa web view. O resultado vem na própria URL:
/// `?item_id=…` quando conecta, `?error=…` quando falha.
struct PluggyConnectSheet: View {
    let url: URL
    let onSuccess: (String) -> Void
    let onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PluggyWebView(url: url, onSuccess: onSuccess, onError: onError)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Conectar banco")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fechar", systemImage: "xmark") { dismiss() }
                    }
                }
        }
        .interactiveDismissDisabled()
    }
}

struct PluggyWebView: UIViewRepresentable {
    let url: URL
    let onSuccess: (String) -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()  // nada do banco fica no aparelho
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        context.coordinator.observe(web)
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSuccess: onSuccess, onError: onError) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onSuccess: (String) -> Void
        let onError: (String) -> Void
        private var observation: NSKeyValueObservation?
        private var finished = false

        init(onSuccess: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onSuccess = onSuccess
            self.onError = onError
        }

        func observe(_ web: WKWebView) {
            // KVO do WKWebView chega na main thread.
            observation = web.observe(\.url, options: [.new]) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.check(web.url) }
            }
        }

        private func check(_ url: URL?) {
            guard !finished, let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
            if let item = items.first(where: { $0.name == "item_id" })?.value, !item.isEmpty {
                finished = true
                onSuccess(item)
            } else if let error = items.first(where: { $0.name == "error" })?.value, !error.isEmpty {
                finished = true
                onError("Pluggy: \(error)")
            }
        }

        // Links que abrem em nova janela (login do banco, Open Finance) ficam na mesma web view.
        func webView(_ web: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil, let url = action.request.url { web.load(URLRequest(url: url)) }
            return nil
        }

        // Esquemas que não são web (app do banco) vão pro sistema.
        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .allow }
            check(url)
            if let scheme = url.scheme, !["http", "https", "about", "blob", "data"].contains(scheme) {
                _ = await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}
