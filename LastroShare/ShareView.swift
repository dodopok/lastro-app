import LastroKit
import SwiftUI
import UniformTypeIdentifiers

/// "Recibo compartilhado": lê o texto ou o print (OCR), mostra o que achou e
/// guarda na caixa de entrada. A confirmação da categoria fica no app, em Recibos.
struct ShareView: View {
    let items: [NSExtensionItem]
    let done: (Bool) -> Void

    @State private var loading = true
    @State private var merchant = ""
    @State private var amountText = ""
    @State private var parsed = ParsedReceipt()
    @State private var error: String?

    private var amount: Money? { BRL.parse(amountText).flatMap { $0.cents > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Lendo o recibo…").textStyle(15).foregroundStyle(.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    VStack(spacing: 0) {
                        field("Onde") {
                            TextField("Loja ou app", text: $merchant).textStyle(15.5, .semibold)
                        }
                        RowDivider()
                        field("Valor") {
                            HStack(spacing: 6) {
                                Text("R$").textStyle(15.5, .semibold).foregroundStyle(.inkQuaternary)
                                TextField("0,00", text: $amountText)
                                    .textStyle(15.5, .semibold).monospacedDigit()
                                    .keyboardType(.decimalPad)
                            }
                        }
                    }
                    .panel(radius: 22, fill: 0.7)

                    Text(parsed.amount == nil
                         ? "Não achei o total. Confira o valor antes de guardar."
                         : "Vai para Recibos no Lastro. Lá você confirma a categoria com um toque.")
                        .textStyle(13).foregroundStyle(.inkSecondary)

                    if let error { Text(error).textStyle(13).foregroundStyle(.negative) }

                    Spacer(minLength: 0)
                    PrimaryButton(title: "Guardar recibo", enabled: amount != nil && !merchant.isEmpty) { save() }
                }
            }
            .foregroundStyle(.ink)
            .padding(20)
            .background { Backdrop() }
            .navigationTitle("Recibo compartilhado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", systemImage: "xmark") { done(false) }
                }
            }
        }
        .tint(.accent)
        .task { await load() }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).textStyle(14).foregroundStyle(.inkSecondary).frame(width: 56, alignment: .leading)
            content()
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private func load() async {
        var lines = items.compactMap { $0.attributedContentText?.string }
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = try? await provider.data(for: .image) {
                lines += (try? await TextRecognizer.lines(in: data)) ?? []
            } else if let type = [UTType.plainText, .url].first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }),
                      let data = try? await provider.data(for: type),
                      let text = String(data: data, encoding: .utf8) {
                lines.append(text)
            }
        }
        let p = ReceiptParser.parse(lines: lines)
        parsed = p
        merchant = p.merchant ?? ""
        amountText = p.amount.map(BRL.digits) ?? ""
        loading = false
    }

    private func save() {
        guard let amount else { return }
        let item = ReceiptInbox.Item(
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            amountCents: amount.cents,
            categorySlug: parsed.categorySlug,
            originLabel: ReceiptInbox.originLabel(app: parsed.app, source: "share"),
            source: "share")
        do {
            try ReceiptInbox.append(item)
            done(true)
        } catch {
            self.error = "Não deu para guardar. O App Group está configurado?"
        }
    }
}

private extension NSItemProvider {
    /// No main actor: NSItemProvider não é Sendable. Só o Data volta pela continuation.
    @MainActor
    func data(for type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            _ = loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let data { cont.resume(returning: data) } else { cont.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }
}
