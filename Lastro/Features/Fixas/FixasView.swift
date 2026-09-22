import LastroKit
import SwiftUI

struct FixasView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: BillDraft?

    var body: some View {
        let bills = store.ledger.activeBills
        let next = store.today.month.next.name.lowercased()

        Screen(title: "Contas fixas", subtitle: "\(bills.count) contas · \(BRL.format(store.ledger.billsTotal))") {
            VStack(alignment: .leading, spacing: 14) {
                step(1, "Cadastra uma vez", "nome, valor, categoria e dia do vencimento")
                step(2, "Todo dia 1 o mês novo já nasce com ela", "nada de recriar linha")
                step(3, "Se quiser, ela se paga", "ligando o piloto, sai sozinha no vencimento", accent: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hero(radius: 26)

            Button { editing = BillDraft(categoryId: store.ledger.activeCategories.first?.id) } label: {
                Label("Nova conta fixa", systemImage: "plus")
                    .textStyle(15.5, .semibold).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(.ink, in: .capsule)
                    .shadow(color: .black.opacity(0.35), radius: 11, y: 10)
            }
            .buttonStyle(PressScale())

            let fixed = bills.filter { !$0.isVariable }
            let variable = bills.filter(\.isVariable)
            if !fixed.isEmpty {
                GroupLabel(text: "Valor sempre igual · renova igual")
                PanelList(data: fixed) { b in BillRow(bill: b) { editing = BillDraft(b) } }
            }
            if !variable.isEmpty {
                GroupLabel(text: "Valor muda todo mês · média dos 3 últimos")
                PanelList(data: variable) { b in BillRow(bill: b) { editing = BillDraft(b) } }
            }
            Text("Alterações valem de \(next) em diante. Meses fechados ficam como estão.")
                .textStyle(12.5).foregroundStyle(.ink.opacity(0.45))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
        .sheet(item: $editing) { draft in
            NavigationStack { FixaEditView(draft: draft) }
                .presentationDetents([.large])
                .presentationCornerRadius(40)
        }
    }

    private func step(_ n: Int, _ title: String, _ sub: String, accent: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").textStyle(13, .bold).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(accent ? Color.accent : Color.ink, in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).textStyle(15, .semibold).foregroundStyle(.ink)
                Text(sub).textStyle(13).foregroundStyle(.inkSecondary)
            }
        }
    }
}

struct BillRow: View {
    @Environment(AppStore.self) private var store
    let bill: Bill
    let tap: () -> Void

    var body: some View {
        let c = store.ledger.category(bill.categoryId)
        Button(action: tap) {
            HStack(spacing: 12) {
                if let c { CategoryIcon(c, size: 34, radius: 11) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(bill.name).textStyle(14.5, .semibold).foregroundStyle(.ink).lineLimit(1)
                    Text("dia \(bill.dueDay) · \(bill.method.label) · \(c?.name ?? "")")
                        .textStyle(12).foregroundStyle(.inkTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text((bill.isVariable ? "~" : "") + BRL.format(bill.amountCents))
                        .textStyle(14.5, .semibold).monospacedDigit().foregroundStyle(.ink)
                    Tag(text: bill.autopay ? "Piloto" : "Manual",
                        color: bill.autopay ? .accent : .ink.opacity(0.5),
                        background: bill.autopay ? Color(Palette.accent).opacity(0.12) : .ink.opacity(0.06))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
        .buttonStyle(RowPressStyle())
    }
}

/// Rascunho editável de uma conta fixa.
struct BillDraft: Identifiable, Hashable {
    var id = UUID()
    var isNew = true
    var name = ""
    var amountText = ""
    var dueDay = 10
    var categoryId: UUID?
    var isVariable = false
    var autopay = false
    var method: PayMethod = .pix
    var pixKey = ""

    init(categoryId: UUID?) { self.categoryId = categoryId }

    init(_ b: Bill) {
        id = b.id
        isNew = false
        name = b.name
        amountText = BRL.digits(b.amountCents)
        dueDay = b.dueDay
        categoryId = b.categoryId
        isVariable = b.isVariable
        autopay = b.autopay
        method = b.method
        pixKey = b.pixKey ?? ""
    }

    var amount: Money? { BRL.parse(amountText) }

    func bill() -> Bill? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, let amount, amount.cents > 0, let categoryId else { return nil }
        return Bill(id: id, name: name.trimmingCharacters(in: .whitespaces), categoryId: categoryId, dueDay: dueDay,
                    amountCents: amount, isVariable: isVariable, autopay: autopay, method: method,
                    pixKey: pixKey.isEmpty ? nil : pixKey)
    }
}

struct FixaEditView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: BillDraft
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    enum Field { case name, amount, pix }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(draft.isNew ? "Nova conta fixa" : "Editar conta fixa").pushedTitle().padding(.horizontal, 4)

                VStack(spacing: 0) {
                    formRow("Nome") {
                        TextField("Aluguel, Luz, Mesada…", text: $draft.name)
                            .textStyle(15.5, .semibold).focused($focus, equals: .name).submitLabel(.next)
                            .onSubmit { focus = .amount }
                    }
                    RowDivider()
                    formRow("Valor") {
                        HStack(spacing: 6) {
                            Text("R$").textStyle(15.5, .semibold).foregroundStyle(.inkQuaternary)
                            TextField("0,00", text: $draft.amountText)
                                .textStyle(15.5, .semibold).monospacedDigit()
                                .keyboardType(.decimalPad).focused($focus, equals: .amount)
                        }
                    }
                    RowDivider()
                    HStack {
                        Text("Vence").textStyle(14).foregroundStyle(.inkSecondary)
                        Spacer()
                        PillStepper(value: "dia \(draft.dueDay)", minWidth: 58,
                                    minus: { draft.dueDay = max(1, draft.dueDay - 1) },
                                    plus: { draft.dueDay = min(28, draft.dueDay + 1) })
                    }
                    .padding(.leading, 16).padding(.trailing, 10).frame(height: 52)
                }
                .panel(radius: 24, fill: 0.66)

                GroupLabel(text: "Categoria")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(store.ledger.activeCategories) { c in
                            SelectChip(title: c.name, selected: draft.categoryId == c.id,
                                       selectedFill: .categoryTint(c.hue, 0.18), selectedStroke: .category(c.hue),
                                       selectedText: .ink, height: 38) {
                                Image(systemName: c.symbol).font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.category(c.hue)).frame(width: 24, height: 24)
                            } action: { draft.categoryId = c.id }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -16)

                VStack(spacing: 0) {
                    toggleRow("O valor muda todo mês", "estimo pela média dos 3 últimos meses", isOn: $draft.isVariable)
                    RowDivider()
                    toggleRow("Pagar sozinho", "entra no piloto automático", isOn: $draft.autopay)
                    if draft.autopay {
                        RowDivider()
                        VStack(spacing: 10) {
                            Picker("Forma", selection: $draft.method) {
                                Text("Pix").tag(PayMethod.pix)
                                Text("Boleto").tag(PayMethod.boleto)
                                Text("Débito").tag(PayMethod.debito)
                            }
                            .pickerStyle(.segmented)
                            if draft.method == .pix {
                                HStack(spacing: 10) {
                                    Text("Chave Pix").textStyle(13).foregroundStyle(.inkTertiary)
                                    TextField("e-mail, CPF ou telefone", text: $draft.pixKey)
                                        .textStyle(14.5, .medium)
                                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                                        .focused($focus, equals: .pix)
                                }
                                .padding(.horizontal, 12).frame(height: 44)
                                .background(.ink.opacity(0.05), in: .rect(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
                        .transition(.opacity)
                    }
                }
                .panel(radius: 24, fill: 0.66)
                .animation(.smooth(duration: 0.22), value: draft.autopay)
                .animation(.smooth(duration: 0.22), value: draft.method)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "faceid").font(.system(size: 16))
                    Text("Acima de \(BRL.rounded(store.ledger.profile.approvalThresholdCents)) eu peço Face ID antes de mandar. Abaixo disso, pago e te aviso.")
                }
                .textStyle(13).foregroundStyle(.inkSecondary).padding(.horizontal, 6)

                PrimaryButton(title: "Salvar", enabled: draft.bill() != nil, height: 52) {
                    guard let bill = draft.bill() else { return }
                    store.save(bill)
                    dismiss()
                }

                if !draft.isNew {
                    Button("Apagar conta fixa", role: .destructive) { confirmDelete = true }
                        .textStyle(15, .semibold)
                        .foregroundStyle(.negative)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .contentShape(.rect)
                }

                Text("Alterações valem de \(store.today.month.next.name.lowercased()) em diante. Meses fechados ficam como estão.")
                    .textStyle(12.5).foregroundStyle(.ink.opacity(0.45))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            .foregroundStyle(.ink)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.canvas)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar", systemImage: "xmark") { dismiss() }
            }
        }
        .confirmationDialog("Apagar \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Apagar conta fixa", role: .destructive) {
                store.deleteBill(draft.id)
                dismiss()
            }
        } message: {
            Text("Sai dos meses seguintes. O que já foi lançado fica.")
        }
        .onAppear { if draft.isNew { focus = .name } }
    }

    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).textStyle(14).foregroundStyle(.inkSecondary).frame(width: 76, alignment: .leading)
            content()
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private func toggleRow(_ title: String, _ sub: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).textStyle(15, .semibold)
                Text(sub).textStyle(12.5).foregroundStyle(.inkTertiary)
            }
        }
        .tint(.positive)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
