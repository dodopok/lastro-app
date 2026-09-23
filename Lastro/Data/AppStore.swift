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
    /// Sheet de lançamento aberta (qualquer tela pode abrir, ex.: "Editar" num recibo).
    var launch: LaunchDraft? = nil
    /// Tela de escanear cupom aberta.
    var scanning = false
    var spendingFilter: SpendingFilter = .todos
    /// Bancos conectados via Pluggy (lidos do servidor).
    private(set) var bankConnections: [BankConnection] = []
    private(set) var isSyncingBanks = false

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
            try await engine.push()
            // Mês corrente e os 3 seguintes (planejamento) já nascem com as fixas.
            for offset in 0...3 { try await remote.openMonth(today.month.adding(months: offset)) }
            try await engine.pull()
            bankConnections = (try? await engine.bankConnections()) ?? []
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

    func signOut() async {
        try? await remote?.signOut()
        try? await engine?.reset()
        phase = .signedOut
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

    func finishOnboarding() { phase = .ready }

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

    func toggleConfirmed(_ e: Entry) {
        if !e.confirmed, CurrentMonth(ledger, month: today.month, today: today.day).needsApproval(e) {
            approval = Approval(entryId: e.id)
            return
        }
        setConfirmed(e.id, !e.confirmed)
    }

    func open(_ draft: LaunchDraft = LaunchDraft()) { launch = draft }

    /// Abre o lançamento depois de um atraso (espera outra tela terminar de fechar).
    func openLauncher(_ draft: LaunchDraft = LaunchDraft(), after delay: Duration) {
        Task {
            try? await Task.sleep(for: delay)
            launch = draft
        }
    }

    func openScanner(after delay: Duration = .zero) {
        Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            scanning = true
        }
    }

    // MARK: recibos

    func confirmReceipt(_ r: Receipt) {
        guard let categoryId = r.categoryId ?? ledger.activeCategories.first?.id else { return }
        addExpense(amount: r.amountCents, categoryId: categoryId, cardId: r.cardId, description: r.merchant,
                   source: r.source, receiptId: r.id)
    }

    func edit(_ r: Receipt) {
        launch = LaunchDraft(amount: r.amountCents, categoryId: r.categoryId, cardId: r.cardId,
                             description: r.merchant, receiptId: r.id)
    }

    /// Recibos que chegaram pela extensão de compartilhar (App Group).
    func drainInbox() {
        let items = ReceiptInbox.drain()
        guard !items.isEmpty else { return }
        let cats = ledger.activeCategories
        for i in items {
            let category = i.categorySlug.flatMap { slug in cats.first { $0.slug == slug } }
                ?? cats.first { $0.nature == .variavel }
            let r = Receipt(id: i.id, merchant: i.merchant, originLabel: i.originLabel,
                            source: i.source == "scan" ? .scan : .share, amountCents: Money(cents: i.amountCents),
                            categoryId: category?.id, cardId: nil, capturedAt: i.capturedAt)
            ledger.receipts.append(r)
            persist(.receipts, r)
        }
        show(items.count == 1 ? "1 recibo chegou" : "\(items.count) recibos chegaram")
    }

    // MARK: planejamento

    func stepBudget(_ month: YearMonth, _ categoryId: UUID, by delta: Money) {
        let current = ledger.budget(for: categoryId, in: month)
        let value = max(.zero, current + delta)
        if let i = ledger.budgets.firstIndex(where: { $0.month == month && $0.categoryId == categoryId && $0.deletedAt == nil }) {
            ledger.budgets[i].amountCents = value
            persist(.monthBudgets, id: ledger.budgets[i].id, ledger.budgets[i])
        } else {
            let b = MonthBudget(month: month, categoryId: categoryId, amountCents: value)
            ledger.budgets.append(b)
            persist(.monthBudgets, id: b.id, b)
        }
    }

    func addExtra(_ month: YearMonth, name: String, amount: Money) {
        let e = MonthExtra(month: month, name: name, amountCents: amount)
        ledger.extras.append(e)
        persist(.monthExtras, id: e.id, e)
    }

    func stepExtra(_ id: UUID, by delta: Money) {
        guard let i = ledger.extras.firstIndex(where: { $0.id == id }) else { return }
        let value = ledger.extras[i].amountCents + delta
        if value.cents <= 0 {
            ledger.extras[i].deletedAt = .now
        } else {
            ledger.extras[i].amountCents = value
        }
        persist(.monthExtras, id: id, ledger.extras[i])
    }

    // MARK: contas fixas

    /// Cria ou edita. Vale dos meses seguintes em diante (o servidor faz o mesmo por trigger).
    func save(_ bill: Bill, announce: Bool = true) {
        let isNew = !ledger.bills.contains { $0.id == bill.id }
        if isNew {
            ledger.bills.append(bill)
        } else if let i = ledger.bills.firstIndex(where: { $0.id == bill.id }) {
            ledger.bills[i] = bill
        }
        propagate(bill, isNew: isNew)
        persist(.bills, id: bill.id, bill)
        guard announce else { return }
        show(isNew ? "Vale a partir de \(today.month.next.name.lowercased())" : "Alterações valem de \(today.month.next.name.lowercased()) em diante")
    }

/// Planilha → contas fixas. Categorias que não existem são criadas (fixas, com cor própria).
    @discardableResult
    func importBills(_ rows: [ImportedBill]) -> Int {
        func key(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
                .trimmingCharacters(in: .whitespaces)
        }
        let hues: [Double] = [265, 160, 75, 225, 20, 320, 290, 195, 345, 45, 120, 10, 250, 140]
        var byName = Dictionary(ledger.activeCategories.map { (key($0.name), $0) }, uniquingKeysWith: { a, _ in a })
        let fallback = ledger.activeCategories.first { $0.nature == .fixo } ?? ledger.activeCategories.first
        let existing = Set(ledger.activeBills.map { key($0.name) })
        var imported = 0

        for row in rows where !existing.contains(key(row.name)) {
            var category = row.categoryName.flatMap { byName[key($0)] } ?? (row.categoryName == nil ? fallback : nil)
            if category == nil {
                let name = row.categoryName ?? "Contas"
                let slug = key(name).replacingOccurrences(of: " ", with: "-")
                let c = BudgetCategory(slug: slug, name: name, hue: hues[ledger.categories.count % hues.count],
                                       nature: .fixo, defaultBudgetCents: .zero, symbol: "circle.grid.2x2",
                                       position: ledger.categories.count)
                ledger.categories.append(c)
                persist(.categories, c)  // antes das contas: chave estrangeira
                byName[key(name)] = c
                category = c
            }
            guard let category else { continue }
            save(Bill(name: row.name, categoryId: category.id, dueDay: row.dueDay, amountCents: row.amount,
                      isVariable: row.isVariable), announce: false)
            imported += 1
        }

        // Orçamento das categorias fixas acompanha o que foi importado.
        for i in ledger.categories.indices where ledger.categories[i].nature == .fixo {
            let total = ledger.activeBills.filter { $0.categoryId == ledger.categories[i].id }.sum(\.amountCents)
            if total > ledger.categories[i].defaultBudgetCents {
                ledger.categories[i].defaultBudgetCents = total
                persist(.categories, ledger.categories[i])
            }
        }
        show(imported == 1 ? "1 conta fixa importada" : "\(imported) contas fixas importadas")
        return imported
    }

    func deleteBill(_ id: UUID) {
        guard let i = ledger.bills.firstIndex(where: { $0.id == id }) else { return }
        ledger.bills[i].deletedAt = .now
        for j in ledger.entries.indices where ledger.entries[j].billId == id && isFutureOpen(ledger.entries[j]) {
            ledger.entries[j].deletedAt = .now
        }
        persist(.bills, id: id, ledger.bills[i])
        show("Conta fixa apagada")
    }

    func setAutopay(_ id: UUID, _ on: Bool) {
        guard let i = ledger.bills.firstIndex(where: { $0.id == id }) else { return }
        ledger.bills[i].autopay = on
        persist(.bills, id: id, ledger.bills[i])
    }

    /// Espelho local do trigger `propagate_bill_change`.
    private func propagate(_ b: Bill, isNew: Bool) {
        let nature = ledger.category(b.categoryId)?.nature
        for j in ledger.entries.indices where ledger.entries[j].billId == b.id && isFutureOpen(ledger.entries[j]) {
            ledger.entries[j].description = b.name
            ledger.entries[j].day = b.dueDay
            ledger.entries[j].categoryId = b.categoryId
            ledger.entries[j].method = b.method
            ledger.entries[j].amountCents = b.amountCents
            ledger.entries[j].estimated = b.isVariable
        }
        // Com servidor, open_month cria as ocorrências dos meses seguintes no próximo sync.
        guard isNew, engine == nil else { return }
        for m in ledger.months where m.month > today.month && m.status != .closed {
            ledger.entries.append(Entry(month: m.month, day: b.dueDay, description: b.name, categoryId: b.categoryId,
                                        amountCents: b.amountCents, method: b.method, confirmed: false,
                                        kind: nature == .parcelado ? .parcela : .fixa, source: .bill,
                                        billId: b.id, estimated: b.isVariable))
        }
    }

    private func isFutureOpen(_ e: Entry) -> Bool {
        !e.confirmed && e.deletedAt == nil && e.month > today.month && ledger.month(e.month)?.status != .closed
    }

    // MARK: perfil

    func stepSafetyFloor(by delta: Money) {
        ledger.profile.safetyFloorCents = max(.zero, ledger.profile.safetyFloorCents + delta)
        persist(.profiles, id: ledger.profile.userId, ledger.profile)
    }

    // MARK: exportar

    /// CSV do mês corrente, para o "Exportar CSV" dos Ajustes.
    func exportCSV() -> URL? {
        let m = today.month
        var lines = ["data;descricao;categoria;valor;forma;confirmado"]
        for e in ledger.entries(in: m).sorted(by: { $0.day < $1.day }) {
            let date = "\(m.year)-\(m.month < 10 ? "0" : "")\(m.month)-\(e.day < 10 ? "0" : "")\(e.day)"
            let fields = [date, e.description, ledger.category(e.categoryId)?.name ?? "",
                          BRL.digits(e.amountCents), ledger.paidWith(e), e.confirmed ? "sim" : "não"]
            lines.append(fields.map { $0.replacingOccurrences(of: ";", with: ",") }.joined(separator: ";"))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lastro-\(m.year)-\(m.month < 10 ? "0" : "")\(m.month).csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Open Finance (Pluggy)

    struct BankSyncSummary: Decodable {
        var accounts = 0, imported = 0, matched = 0, created = 0, ignored = 0

        var message: String {
            if imported == 0 { return "Nada novo no banco" }
            var parts: [String] = []
            if matched > 0 { parts.append("\(matched) conferido\(matched == 1 ? "" : "s")") }
            if created > 0 { parts.append("\(created) novo\(created == 1 ? "" : "s")") }
            return parts.isEmpty ? "Tudo já batia com o banco" : parts.joined(separator: " · ")
        }
    }

    struct PluggyToken: Decodable {
        let connectToken: String
        let sandbox: Bool
    }

    enum BankError: LocalizedError {
        case offline
        var errorDescription: String? { "Conectar banco precisa do servidor (Supabase) configurado." }
    }

    /// Token de uso único para abrir o widget da Pluggy. `itemId` = reconectar um banco existente.
    func pluggyToken(itemId: String? = nil) async throws -> PluggyToken {
        guard let remote else { throw BankError.offline }
        let data = try await remote.pluggy("POST", "token", body: itemId.map { ["itemId": $0] } ?? [:])
        return try JSONDecoder().decode(PluggyToken.self, from: data)
    }

    /// Depois do widget: registra o item e faz a 1ª sincronização (mês corrente).
    func connectBank(itemId: String) async {
        guard let remote else { return }
        isSyncingBanks = true
        defer { isSyncingBanks = false }
        do {
            let data = try await remote.pluggy("POST", "items", body: ["itemId": itemId])
            let summary = try JSONDecoder().decode(BankSyncSummary.self, from: data)
            await refresh()
            show("Banco conectado · \(summary.message)")
        } catch {
            show(serverMessage(error) ?? "Não deu para conectar o banco")
        }
    }

    func syncBanks() async {
        guard let remote, !isSyncingBanks else { return }
        isSyncingBanks = true
        defer { isSyncingBanks = false }
        do {
            let data = try await remote.pluggy("POST", "sync", body: [:])
            let summary = try JSONDecoder().decode(BankSyncSummary.self, from: data)
            await refresh()
            show(summary.message)
        } catch {
            show("Não deu para falar com o banco agora")
        }
    }

    func disconnect(_ connection: BankConnection) async {
        guard let remote else { return }
        do {
            _ = try await remote.pluggy("DELETE", "items/\(connection.id.uuidString.lowercased())", body: [:])
            bankConnections.removeAll { $0.id == connection.id }
            await refresh()
            show("\(connection.connectorName) desconectado")
        } catch {
            show("Não deu para desconectar agora")
        }
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
        persist(table, id: value.id, value)
    }

    private func persist<T: Encodable & Sendable>(_ table: SyncTable, id: UUID, _ value: T) {
        guard let engine else { return }
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
