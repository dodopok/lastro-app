import LastroKit
import SwiftUI

// MARK: - Mais (aba)

struct MaisView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let l = store.ledger
        let m = CurrentMonth(l, month: store.today.month, today: store.today.day)
        let receipts = l.pendingReceipts.count
        let months = l.emergencyMonths.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR")))
        let items: [MenuItem] = [
            MenuItem(title: "Recibos", sub: receipts > 0 ? "\(receipts) esperando confirmação" : "nada novo", symbol: "tray", hue: 262, route: .recibos),
            MenuItem(title: "Cartões", sub: "\(BRL.rounded(m.openStatements)) em faturas abertas", symbol: "creditcard", hue: 305, route: .cartoes),
            MenuItem(title: "Dívidas", sub: "\(BRL.rounded(l.openDebt)) em aberto", symbol: "doc.plaintext", hue: 45, route: .dividas),
            MenuItem(title: "Metas e reservas", sub: "\(months) meses de reserva", symbol: "target", hue: 155, route: .metas),
            MenuItem(title: "Contas fixas", sub: "\(l.activeBills.count) contas · \(BRL.rounded(l.billsTotal))", symbol: "arrow.2.squarepath", hue: 225, route: .fixas),
            MenuItem(title: "Planejar \(store.today.month.next.name.lowercased())", sub: "orçamento do mês seguinte", symbol: "calendar", hue: 195, route: .planejar(store.today.month.next)),
            MenuItem(title: "Ajustes", sub: "dados, atalhos, Face ID", symbol: "slider.horizontal.3", hue: 280, route: .ajustes),
        ]

        Screen(title: "Mais", style: .tab) {
            PanelList(data: items) { item in
                NavigationLink(value: item.route) {
                    HStack(spacing: 12) {
                        CategoryIcon(symbol: item.symbol, hue: item.hue, size: 38, radius: 12)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title).textStyle(15.5, .semibold).foregroundStyle(.ink)
                            Text(item.sub).textStyle(12.5).monospacedDigit().foregroundStyle(.inkTertiary)
                        }
                        Spacer(minLength: 0)
                        Chevron()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .buttonStyle(RowPressStyle())
            }
        }
    }

    struct MenuItem: Identifiable {
        let title: String
        let sub: String
        let symbol: String
        let hue: Double
        let route: Route
        var id: String { title }
    }
}

// MARK: - Dívidas

struct DividasView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let l = store.ledger
        let s = DebtSummary(l, current: store.today.month)
        let share = s.shareOfIncome(l.income(in: store.today.month))

        Screen(title: "Dívidas") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total em aberto").textStyle(14, .semibold).foregroundStyle(.ink.opacity(0.6))
                BigAmount(text: BRL.format(s.open), size: 42)
                if let free = s.freeAt {
                    Text("Livre em \(Text("\(free.name.lowercased()) de \(String(free.year))").fontWeight(.bold).foregroundStyle(Color.ink)) no ritmo atual.")
                        .textStyle(14).foregroundStyle(.ink.opacity(0.6))
                } else {
                    Text("Nada em aberto.").textStyle(14).foregroundStyle(.positive)
                }
                HStack(spacing: 10) {
                    ProgressBar(fraction: share, color: Color(OKLCH(0.6, 0.15, 45)), height: 8)
                    Text(verbatim: "\(Int((share * 100).rounded()))% da renda").textStyle(12.5).foregroundStyle(.inkSecondary).fixedSize()
                }
                .padding(.top, 10)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hero(radius: 30)

            ForEach(l.debts.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }) { d in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(d.name).textStyle(16, .bold)
                            Text(d.isPaidOff ? (d.description ?? "quitado")
                                 : "\(d.description ?? "") · \(d.installmentsPaid) de \(d.installmentsTotal)")
                                .textStyle(12.5).foregroundStyle(.inkTertiary)
                        }
                        Spacer()
                        Text(d.installmentCents.cents > 0 ? BRL.format(d.installmentCents) + "/mês" : "—")
                            .textStyle(14, .semibold).monospacedDigit()
                    }
                    ProgressBar(fraction: d.progress, color: d.isPaidOff ? .positive : .ink, height: 6)
                    HStack {
                        Text("pago \(BRL.rounded(d.paidCents))")
                        Spacer()
                        Text(d.isPaidOff ? "quitado" : "restam \(BRL.rounded(d.remaining))")
                            .fontWeight(.semibold).foregroundStyle(d.isPaidOff ? Color.positive : Color.ink)
                    }
                    .textStyle(12.5).monospacedDigit().foregroundStyle(.inkTertiary)
                }
                .foregroundStyle(.ink)
                .padding(.horizontal, 18).padding(.vertical, 16)
                .panel()
            }
        }
    }
}

// MARK: - Metas e reservas

struct MetasView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let l = store.ledger
        let months = l.emergencyMonths
        let fixed = l.billsTotal
        let emergency = l.goals.first { $0.kind == .emergency && $0.deletedAt == nil }
        let missing = max(.zero, fixed * 6 - (emergency?.savedCents ?? .zero))

        Screen(title: "Metas e reservas") {
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.track, lineWidth: 14)
                    Circle().trim(from: 0, to: min(1, months / 6))
                        .stroke(Color.positive, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Text(months.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR"))))
                            .textStyle(46, .bold, tracking: -0.05)
                        Text("meses de reserva").textStyle(12.5).foregroundStyle(.inkSecondary)
                    }
                }
                .frame(width: 168, height: 168)
                .padding(7)

                HStack {
                    figure("Custo fixo mensal", BRL.rounded(fixed))
                    figure("Falta para 6 meses", BRL.rounded(missing))
                }
            }
            .foregroundStyle(.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20).padding(.vertical, 24)
            .hero(radius: 30)

            ForEach(l.goals.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }) { g in
                let target = l.target(of: g)
                let pct = target.cents > 0 ? Double(g.savedCents.cents) / Double(target.cents) : 0
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(g.name).textStyle(16, .bold)
                            Text(g.description ?? "").textStyle(12.5).foregroundStyle(.inkTertiary)
                        }
                        Spacer()
                        Text(verbatim: "\(Int((pct * 100).rounded()))%").textStyle(14, .bold).foregroundStyle(.inkTertiary)
                    }
                    ProgressBar(fraction: pct, color: Color(OKLCH(0.56, 0.14, g.hue)), height: 6)
                    Text("\(Text(BRL.rounded(g.savedCents)).fontWeight(.bold)) \(Text("de \(BRL.rounded(target))").foregroundStyle(Color.ink.opacity(0.5)))")
                        .textStyle(13).monospacedDigit()
                }
                .foregroundStyle(.ink)
                .padding(.horizontal, 18).padding(.vertical, 16)
                .panel()
            }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(label).textStyle(12).foregroundStyle(.inkTertiary)
            Text(value).textStyle(17, .bold).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Recibos

struct RecibosView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let receipts = store.ledger.receipts
            .filter { $0.deletedAt == nil && $0.status != .discarded }
            .sorted { $0.capturedAt > $1.capturedAt }

        Screen(title: "Recibos", subtitle: "chegaram pelo compartilhar e pelo scan", spacing: 12) {
            if receipts.isEmpty {
                Text("Nenhum recibo por enquanto.").textStyle(14).foregroundStyle(.inkTertiary).padding(.horizontal, 4)
            }
            ForEach(receipts) { r in
                ReceiptCard(receipt: r)
            }
        }
        .animation(.smooth(duration: 0.3), value: receipts.map(\.status))
    }
}

struct ReceiptCard: View {
    @Environment(AppStore.self) private var store
    let receipt: Receipt

    var body: some View {
        let c = receipt.categoryId.flatMap { store.ledger.category($0) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let c { CategoryIcon(c, size: 40, radius: 13) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(receipt.merchant).textStyle(16, .semibold)
                    Text(receipt.originLabel).textStyle(12.5).foregroundStyle(.inkTertiary)
                }
                Spacer()
                Text(BRL.format(receipt.amountCents)).textStyle(18, .bold, tracking: -0.02).monospacedDigit()
            }
            if receipt.status == .pending {
                HStack(spacing: 8) {
                    Button { store.confirmReceipt(receipt) } label: {
                        Text("Confirmar em \(c?.name ?? "Gastos")")
                            .textStyle(14, .semibold).foregroundStyle(.white).lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(.ink, in: .capsule)
                    }
                    .buttonStyle(PressScale())
                    Button { store.edit(receipt) } label: {
                        Text("Editar").textStyle(14, .semibold).foregroundStyle(.ink)
                            .padding(.horizontal, 18).frame(height: 42)
                            .background(.ink.opacity(0.07), in: .capsule)
                    }
                    .buttonStyle(PressScale())
                }
            } else {
                Label("Salvo em \(c?.name ?? "Gastos")", systemImage: "checkmark")
                    .textStyle(13.5, .semibold).foregroundStyle(.positive)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.ink)
        .padding(16)
        .panel(radius: 24, fill: 0.62)
    }
}

// MARK: - Ajustes

struct AjustesView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("share.enabled") private var share = true
    @AppStorage("siri.enabled") private var siri = false
    @AppStorage("widget.enabled") private var widget = true
    @AppStorage("faceid.onOpen") private var faceID = true
    @AppStorage("reminder.enabled") private var reminder = true
    @State private var csv: URL?
    @State private var importing = false

    var body: some View {
        Screen(title: "Ajustes", spacing: 10) {
            group("Dados") {
                row("Importar planilha", "doc.text") { importing = true }
                RowDivider()
                link("Bancos conectados", "building.columns",
                     note: store.bankConnections.isEmpty ? "Pluggy" : "\(store.bankConnections.count)", route: .bancos)
                RowDivider()
                if let csv {
                    ShareLink(item: csv) { rowLabel("Exportar CSV", "square.and.arrow.down", note: csv.lastPathComponent) }
                        .buttonStyle(RowPressStyle())
                } else {
                    row("Exportar CSV", "square.and.arrow.down") { csv = store.exportCSV() }
                }
            }
            group("Lançar rápido") {
                toggle("Extensão de compartilhamento", "square.and.arrow.up", $share)
                RowDivider()
                row("Escanear cupom", "text.viewfinder") { store.openScanner() }
                RowDivider()
                toggle("Atalho da Siri", "mic", $siri)
                RowDivider()
                toggle("Widget e Lock Screen", "square.grid.2x2", $widget)
            }
            group("Orçamento") {
                link("Categorias", "tag", note: "\(store.ledger.activeCategories.count)", route: nil)
                RowDivider()
                link("Contas fixas", "arrow.2.squarepath", note: "\(store.ledger.activeBills.count)", route: .fixas)
                RowDivider()
                link("Metas e reservas", "target", route: .metas)
                RowDivider()
                link("Dívidas", "doc.plaintext", route: .dividas)
            }
            group("App") {
                toggle("Face ID ao abrir", "faceid", $faceID, sub: "esconde valores no App Switcher")
                RowDivider()
                toggle("Lembrete de confirmação", "bell", $reminder, sub: "todo dia às 21h")
            }
            if !store.isDemo {
                Button("Sair da conta", role: .destructive) { Task { await store.signOut() } }
                    .textStyle(15, .semibold).foregroundStyle(.negative)
                    .frame(maxWidth: .infinity).frame(height: 46)
            }
        }
        .sheet(isPresented: $importing) { ImportarView() }
    }


    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupLabel(text: title)
            VStack(spacing: 0) { content() }.panel()
        }
        .padding(.bottom, 6)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(.ink)
            .frame(width: 30, height: 30)
            .background(.ink.opacity(0.06), in: .rect(cornerRadius: 9, style: .continuous))
    }

    private func rowLabel(_ title: String, _ symbol: String, note: String? = nil) -> some View {
        HStack(spacing: 12) {
            icon(symbol)
            Text(title).textStyle(15, .medium).foregroundStyle(.ink)
            Spacer()
            if let note { Text(note).textStyle(14).foregroundStyle(.ink.opacity(0.45)).lineLimit(1) }
            Chevron()
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
    }

    private func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, symbol) }.buttonStyle(RowPressStyle())
    }

    @ViewBuilder
    private func link(_ title: String, _ symbol: String, note: String? = nil, route: Route?) -> some View {
        if let route {
            NavigationLink(value: route) { rowLabel(title, symbol, note: note) }.buttonStyle(RowPressStyle())
        } else {
            rowLabel(title, symbol, note: note)
        }
    }

    private func toggle(_ title: String, _ symbol: String, _ isOn: Binding<Bool>, sub: String? = nil) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                icon(symbol)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).textStyle(15, .medium).foregroundStyle(.ink)
                    if let sub { Text(sub).textStyle(12).foregroundStyle(.inkTertiary) }
                }
            }
        }
        .tint(.positive)
        .padding(.horizontal, 14).padding(.vertical, 9).frame(minHeight: 50)
    }
}
