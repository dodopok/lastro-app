import LastroKit
import SwiftUI

struct PilotoView: View {
    @Environment(AppStore.self) private var store

    enum Status {
        case manual, paid, approve, scheduled

        var label: String {
            switch self {
            case .manual: "Manual"
            case .paid: "Pago"
            case .approve: "Aprovar"
            case .scheduled: "Agendado"
            }
        }

        var colors: (fg: Color, bg: Color) {
            switch self {
            case .manual: (.ink.opacity(0.55), .ink.opacity(0.07))
            case .paid: (.positive, Color(Palette.green).opacity(0.14))
            case .approve: (.warning, Color(Palette.amber).opacity(0.16))
            case .scheduled: (.accent, Color(Palette.accent).opacity(0.12))
            }
        }
    }

    var body: some View {
        let l = store.ledger
        let m = CurrentMonth(l, month: store.today.month, today: store.today.day)
        let bills = l.activeBills
        let floor = l.profile.safetyFloorCents
        let ok = m.isAboveSafetyFloor

        Screen(title: "Piloto automático", subtitle: "\(bills.filter(\.autopay).count) de \(bills.count) contas no piloto", style: .tab) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pago sozinho em \(m.month.name.lowercased())").textStyle(14, .semibold).foregroundStyle(.ink.opacity(0.6))
                BigAmount(text: BRL.format(m.autopaidTotal))
                Text(m.nextAutopay.map { "próxima: \($0.name), dia \($0.dueDay)" } ?? "nada agendado")
                    .textStyle(13.5).foregroundStyle(.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .hero(radius: 30)
            .background(alignment: .topLeading) {
                Ellipse().fill(Color(OKLCH(0.7, 0.17, 262))).frame(width: 220, height: 180)
                    .blur(radius: 50).opacity(0.35).offset(x: -10, y: -20).allowsHitTesting(false)
            }

            // Trava de segurança
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "lock").font(.system(size: 17, weight: .medium))
                        .frame(width: 38, height: 38)
                        .background(.ink.opacity(0.07), in: .rect(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Trava de segurança").textStyle(15, .semibold)
                        Text("nada é pago abaixo deste saldo").textStyle(12.5).foregroundStyle(.inkTertiary)
                    }
                    Spacer()
                }
                HStack {
                    roundButton("minus") { store.stepSafetyFloor(by: Money(cents: -50_000)) }
                    Spacer()
                    BigAmount(text: BRL.rounded(floor), size: 30)
                    Spacer()
                    roundButton("plus") { store.stepSafetyFloor(by: Money(cents: 50_000)) }
                }
                Text(ok ? "Saldo confirmado \(BRL.rounded(m.confirmedBalance)) · acima da trava"
                        : "Saldo \(BRL.rounded(m.confirmedBalance)) · pagamentos pausados")
                    .textStyle(12.5, .semibold)
                    .foregroundStyle(ok ? Color.positive : Color.negative)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(.ink)
            .padding(.horizontal, 18).padding(.vertical, 16)
            .panel(radius: 24)
            .animation(.smooth(duration: 0.22), value: ok)

            SectionHeader(title: "Contas")
            PanelList(data: bills) { b in
                let st = pilotStatus(b, month: m)
                BillPilotRow(bill: b, status: st) {
                    if st == .approve, let e = m.entries.first(where: { $0.billId == b.id }) {
                        store.approval = .init(entryId: e.id)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "faceid").font(.system(size: 16))
                Text("Acima de \(BRL.rounded(store.ledger.profile.approvalThresholdCents)) eu peço Face ID antes de mandar. Abaixo disso, pago e te aviso.")
            }
            .textStyle(13).foregroundStyle(.inkSecondary).padding(.horizontal, 6)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "server.rack").font(.system(size: 15))
                Text("Os pagamentos saem pelo servidor (/pagamentos). Por enquanto o provedor é o sandbox: nada é enviado de verdade.")
            }
            .textStyle(12.5).foregroundStyle(.ink.opacity(0.45)).padding(.horizontal, 6)
        }
    }

    private func pilotStatus(_ b: Bill, month m: CurrentMonth) -> Status {
        guard b.autopay else { return .manual }
        let e = m.entries.first { $0.billId == b.id }
        if e?.confirmed == true { return .paid }
        if b.amountCents > store.ledger.profile.approvalThresholdCents, b.dueDay <= m.today { return .approve }
        return .scheduled
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.ink.opacity(0.06), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(PressScale(scale: 0.92))
        .foregroundStyle(.ink)
    }
}

struct BillPilotRow: View {
    @Environment(AppStore.self) private var store
    let bill: Bill
    let status: PilotoView.Status
    let tap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: tap) {
                HStack(spacing: 12) {
                    if let c = store.ledger.category(bill.categoryId) { CategoryIcon(c, size: 34, radius: 11) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bill.name).textStyle(14.5, .semibold).foregroundStyle(.ink).lineLimit(1)
                        HStack(spacing: 6) {
                            Tag(text: status.label, color: status.colors.fg, background: status.colors.bg)
                            Text((bill.isVariable ? "~" : "") + BRL.format(bill.amountCents))
                                .textStyle(12).monospacedDigit().foregroundStyle(.inkTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(status != .approve)

            Toggle("Pagar sozinho", isOn: Binding(get: { bill.autopay }, set: { store.setAutopay(bill.id, $0) }))
                .labelsHidden()
                .tint(.positive)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .animation(.smooth(duration: 0.22), value: status)
    }
}
