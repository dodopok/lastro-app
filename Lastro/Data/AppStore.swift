import Foundation
import LastroKit
import LocalAuthentication
import Observation

/// Estado do app. As telas leem `ledger` e chamam as ações; cada ação muda o
/// ledger na hora (otimista), grava no cache/fila e dispara um sync.
@MainActor
@Observable
final class AppStore {
    enum Phase: Equatable { case loading, signedOut, onboarding, ready }

    struct Toast: Equatable, Identifiable {
        let id = UUID()
        let message: String
    }

    struct Approval: Equatable {
        enum Step: Equatable { case ask, scanning }
        let entryId: UUID
        var step: Step = .ask
    }

    private(set) var phase: Phase = .loading
    private(set) var ledger: Ledger
    private(set) var today: (month: YearMonth, day: Int)
    private(set) var isSyncing = false
    private(set) var lastError: String? = nil

    var selectedMonth: YearMonth
    var heroIndex = 0
    var toast: Toast? = nil
    var approval: Approval? = nil

    let isDemo: Bool
    private let engine: SyncEngine?
    let remote: SupabaseRemote?

    init() {
        var remote: SupabaseRemote?
        var engine: SyncEngine?
        if !AppConfig.isDemo, let url = AppConfig.supabaseURL, let key = AppConfig.supabaseKey,
           let container = try? LocalCache.makeContainer() {
            let r = SupabaseRemote(url: url, key: key)
            remote = r
            engine = SyncEngine(remote: r, cache: LocalCache(modelContainer: container))
        }
        let online = engine != nil
        let now: (month: YearMonth, day: Int) = online ? Self.now() : (DemoData.current, DemoData.today)
        self.remote = remote
        self.engine = engine
        self.isDemo = !online
        self.today = now
        self.selectedMonth = now.month
        self.ledger = online ? Ledger(profile: Profile(userId: UUID(), monthlyIncomeCents: .zero)) : DemoData.ledger()
        self.phase = online ? .loading : .ready
    }

    /// Para previews: dados do protótipo, sem rede.
    static func preview() -> AppStore {
        let s = AppStore(demo: ())
        return s
    }

    private init(demo: Void) {
        isDemo = true
        remote = nil
        engine = nil
        today = (DemoData.current, DemoData.today)
        ledger = DemoData.ledger()
        selectedMonth = DemoData.current
        phase = .ready
    }

    /// Mês e dia de hoje no fuso do usuário.
    static func now(timeZone: String = "America/Sao_Paulo") -> (month: YearMonth, day: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZone) ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: .now)
        return (YearMonth(year: c.year!, month: c.month!), c.day!)
    }

    // MARK: ciclo de vida

    func start() async {
        guard let engine, let remote else { return }
        if let cached = try? await engine.loadLedger() {
            ledger = cached
            phase = .ready
        }
        guard await remote.userId != nil else {
            phase = .signedOut
            return
        }
        await refresh()
    }

    func refresh() async {
        guard let engine, let remote, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await remote.openMonth(today.month)
            try await engine.sync()
            if let fresh = try await engine.loadLedger() {
                ledger = fresh
                phase = fresh.categories.isEmpty ? .onboarding : .ready
            } else {
                phase = .onboarding
            }
            lastError = nil
        } catch {
            // Offline: segue com o cache; a fila sobe no próximo sync.
            lastError = error.localizedDescription
            if phase == .loading { phase = .ready }
        }
    }

    func didSignIn() async {
        phase = .loading
        await refresh()
    }

    // MARK: onboarding

    func importTemplate() async {
        if let remote {
            do {
                try await remote.seedDemo()
                await refresh()
            } catch {
                show("Não deu para importar: \(error.localizedDescription)")
                return
            }
        }
        phase = .ready
        show("\(ledger.activeBills.count) contas fixas importadas")
    }

    func startEmpty() {
        phase = .ready
        show("Começando do zero")
    }

    // MARK: ações

    func show(_ message: String) {
        toast = Toast(message: message)
        let id = toast?.id
        Task {
            try? await Task.sleep(for: .seconds(2.3))
            if toast?.id == id { toast = nil }
        }
    }

    func setConfirmed(_ entryId: UUID, _ confirmed: Bool) {
        guard let i = ledger.entries.firstIndex(where: { $0.id == entryId }) else { return }
        ledger.entries[i].confirmed = confirmed
        persist(.transactions, ledger.entries[i])
    }

    /// Toque no círculo de "Para confirmar". Acima do limite com piloto, pede Face ID.
    func tapPending(_ e: Entry) {
        let month = CurrentMonth(ledger, month: today.month, today: today.day)
        if month.needsApproval(e) {
            approval = Approval(entryId: e.id)
        } else {
            setConfirmed(e.id, true)
            show("\(e.description) confirmado")
        }
    }

    @discardableResult
    func addExpense(amount: Money, categoryId: UUID, cardId: UUID?, description: String?,
                    source: TxSource = .manual, receiptId: UUID? = nil) -> Entry {
        let category = ledger.category(categoryId)
        let entry = Entry(month: today.month, day: today.day, description: description ?? category?.name ?? "Gasto",
                          categoryId: categoryId, amountCents: amount, method: cardId == nil ? .pix : .cartao,
                          cardId: cardId, confirmed: true, kind: .variavel, source: source)
        ledger.entries.append(entry)
        persist(.transactions, entry)
        if let receiptId, let i = ledger.receipts.firstIndex(where: { $0.id == receiptId }) {
            ledger.receipts[i].status = .saved
            ledger.receipts[i].transactionId = entry.id
            persist(.receipts, ledger.receipts[i])
        }
        show("\(BRL.format(amount)) salvo em \(category?.name ?? "Gastos")")
        return entry
    }

    // MARK: piloto · Face ID

    func cancelApproval() { approval = nil }

    func authorize() async {
        guard var a = approval, let entry = ledger.entries.first(where: { $0.id == a.entryId }) else { return }
        a.step = .scanning
        approval = a

        let context = LAContext()
        let reason = "Autorizar Pix de \(BRL.format(entry.amountCents))"
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
                approval = nil
                return
            }
            if let remote, let bill = entry.billId.flatMap({ ledger.bill($0) }) {
                let request = PaymentRequest(
                    tipo: bill.method == .boleto ? "boleto" : "pix", valor: entry.amountCents.cents,
                    destino: bill.pixKey ?? "", data: "\(today.month.iso.prefix(8))\(entry.day < 10 ? "0" : "")\(entry.day)",
                    exigeAprovacao: true, contaId: bill.id, lancamentoId: entry.id, chave: UUID().uuidString)
                let created = try LastroCoding.decoder.decode(Payment.self, from: await remote.requestPayment(request))
                let result = try LastroCoding.decoder.decode(Payment.self, from: await remote.approvePayment(created.id))
                guard result.status == .paid || result.status == .processing else {
                    approval = nil
                    show(result.failureReason ?? "Pagamento não saiu")
                    return
                }
            }
            approval = nil
            setConfirmed(entry.id, true)
            show("Pix de \(BRL.format(entry.amountCents)) enviado")
        } catch {
            approval = nil
            show(error is LAError ? "Face ID cancelado" : "Não deu para pagar agora")
        }
    }

    // MARK: persistência

    private func persist<T: Encodable & Sendable>(_ table: SyncTable, _ value: T) where T: Identifiable, T.ID == UUID {
        guard let engine else { return }
        let id = value.id
        Task {
            do {
                try await engine.save(table, id: id, value)
                await refresh()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
