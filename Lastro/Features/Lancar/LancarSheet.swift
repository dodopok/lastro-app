import LastroKit
import SwiftUI

/// Pré-preenchimento do lançamento (ex.: "Editar" num recibo).
struct LaunchDraft: Identifiable, Hashable {
    let id = UUID()
    var amount: Money?
    var categoryId: UUID?
    var cardId: UUID?
    var description: String?
    var receiptId: UUID?
}

/// "Novo gasto": teclado próprio, categoria e forma de pagamento num toque.
struct LancarSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let draft: LaunchDraft
    var onScan: () -> Void = {}
    var onReceipts: () -> Void = {}

    @State private var input = AmountInput()
    @State private var categoryId: UUID?
    @State private var cardId: UUID?  // nil = Pix/débito

    var body: some View {
        let categories = store.ledger.activeCategories
        let selected = categoryId.flatMap { store.ledger.category($0) } ?? categories.first

        VStack(spacing: 12) {
            header
            amount
            Text("hoje, \(store.today.day) de \(store.today.month.name.lowercased())")
                .textStyle(12.5).foregroundStyle(.ink.opacity(0.45))
                .padding(.top, -6)

            categoryChips(categories, selected: selected)
            cardChips
            keypad

            PrimaryButton(title: "Salvar em \(selected?.name ?? "…")", enabled: input.money.cents > 0) {
                guard let selected, input.money.cents > 0 else { return }
                store.addExpense(amount: input.money, categoryId: selected.id, cardId: cardId,
                                 description: draft.description, receiptId: draft.receiptId)
                dismiss()
            }

            HStack(spacing: 22) {
                Button { dismiss(); onScan() } label: {
                    Label("Escanear cupom", systemImage: "text.viewfinder")
                        .padding(.vertical, 8).contentShape(.rect)
                }
                Button { dismiss(); onReceipts() } label: {
                    Label("Recibo compartilhado", systemImage: "square.and.arrow.up")
                        .padding(.vertical, 8).contentShape(.rect)
                }
            }
            .textStyle(13.5, .semibold)
            .foregroundStyle(Color(OKLCH(0.5, 0.2, 262)))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .sensoryFeedback(.impact(weight: .light), trigger: input)
        .onAppear {
            if let a = draft.amount { input = AmountInput(a) }
            categoryId = draft.categoryId
                ?? categories.first { $0.slug == "rango" }?.id
                ?? categories.first { $0.nature == .variavel }?.id
            cardId = draft.cardId
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.ink.opacity(0.06), in: .circle)
                    .contentShape(.circle)
            }
            .accessibilityLabel("Fechar")
            Spacer()
            Text(draft.description ?? "Novo gasto").textStyle(16, .semibold)
            Spacer()
            Button { dismiss(); onScan() } label: {
                Image(systemName: "text.viewfinder").font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(.ink.opacity(0.06), in: .circle)
                    .contentShape(.circle)
            }
            .accessibilityLabel("Escanear cupom")
        }
        .foregroundStyle(.ink)
        .buttonStyle(.plain)
    }

    private var amount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("R$").textStyle(24, .semibold)
            Text(input.isEmpty ? "0" : input.display)
                .textStyle(56, .bold, tracking: -0.05)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.15), value: input)
        }
        .monospacedDigit()
        .foregroundStyle(input.isEmpty ? Color.ink.opacity(0.22) : Color.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Valor, \(BRL.format(input.money))")
    }

    private func categoryChips(_ categories: [BudgetCategory], selected: BudgetCategory?) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(categories) { c in
                    SelectChip(title: c.name, selected: c.id == selected?.id,
                               selectedFill: .categoryTint(c.hue, 0.2), selectedStroke: .category(c.hue),
                               selectedText: .ink) {
                        Image(systemName: c.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.category(c.hue))
                            .frame(width: 24, height: 24)
                    } action: {
                        categoryId = c.id
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
        .sensoryFeedback(.selection, trigger: categoryId)
    }

    private var cardChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                SelectChip(title: "Pix/débito", selected: cardId == nil) { cardId = nil }
                ForEach(store.ledger.activeCards) { c in
                    SelectChip(title: c.name, selected: cardId == c.id) { cardId = c.id }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
    }

    private static func label(_ k: AmountInput.Key) -> String {
        switch k {
        case .digit(let d): "\(d)"
        case .comma: "Vírgula"
        case .delete: "Apagar"
        }
    }

    private var keypad: some View {
        let keys: [AmountInput.Key] = [.digit(1), .digit(2), .digit(3), .digit(4), .digit(5), .digit(6),
                                       .digit(7), .digit(8), .digit(9), .comma, .digit(0), .delete]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(keys, id: \.self) { k in
                Button { input.press(k) } label: {
                    Group {
                        switch k {
                        case .digit(let d): Text("\(d)")
                        case .comma: Text(",")
                        case .delete: Image(systemName: "delete.left").font(.system(size: 22, weight: .regular))
                        }
                    }
                    .textStyle(25, .medium)
                    .foregroundStyle(.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(.rect)
                }
                .buttonStyle(KeyStyle())
                .accessibilityLabel(Self.label(k))
            }
        }
    }
}

private struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .background(configuration.isPressed ? Color.ink.opacity(0.09) : .clear,
                        in: .rect(cornerRadius: 16, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    Color.canvas
        .sheet(isPresented: .constant(true)) {
            LancarSheet(draft: LaunchDraft())
                .presentationDetents([.large])
        }
        .environment(AppStore.preview())
}
