import LastroKit
import SwiftUI
import UniformTypeIdentifiers

/// Planilha (CSV) → contas fixas, com prévia antes de trazer.
struct ImportarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void = {}

    @State private var picking = false
    @State private var rows: [ImportedBill] = []
    @State private var fileName: String?
    @State private var error: String?

    var body: some View {
        let existing = Set(store.ledger.activeBills.map { $0.name.lowercased() })
        let fresh = rows.filter { !existing.contains($0.name.lowercased()) }
        let known = Set(store.ledger.activeCategories.map { $0.name.lowercased() })
        let newCategories = Set(fresh.compactMap(\.categoryName).filter { !known.contains($0.lowercased()) })

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Importar planilha").pushedTitle().padding(.horizontal, 4)

                    if rows.isEmpty {
                        Callout(symbol: "tablecells", eyebrow: "Como exportar",
                                text: "Na planilha, abra a aba das despesas e salve como CSV (Arquivo › Baixar › CSV no Google Sheets; Arquivo › Exportar › CSV no Numbers). Preciso das colunas Descrição e Valor; Categoria, Vencimento e Variável são opcionais.")
                        Button { picking = true } label: {
                            Label("Escolher arquivo CSV", systemImage: "doc.badge.plus")
                                .textStyle(15.5, .semibold).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(.ink, in: .capsule)
                        }
                        .buttonStyle(PressScale())
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fileName ?? "Planilha").textStyle(13).foregroundStyle(.inkTertiary)
                            BigAmount(text: BRL.format(fresh.sum(\.amount)), size: 34)
                            Text("\(fresh.count) contas novas" + (newCategories.isEmpty ? "" : " · \(newCategories.count) categorias novas")
                                 + (rows.count > fresh.count ? " · \(rows.count - fresh.count) já existem" : ""))
                                .textStyle(13.5).foregroundStyle(.inkSecondary)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hero(radius: 28)

                        PanelList(data: rows) { r in
                            let dup = existing.contains(r.name.lowercased())
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(r.name).textStyle(14.5, .semibold).lineLimit(1)
                                    Text("dia \(r.dueDay)" + (r.categoryName.map { " · \($0)" } ?? "") + (r.isVariable ? " · varia" : ""))
                                        .textStyle(12).foregroundStyle(.inkTertiary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(BRL.format(r.amount)).textStyle(14.5, .semibold).monospacedDigit()
                                    if dup { Tag(text: "já existe") }
                                }
                            }
                            .foregroundStyle(.ink)
                            .opacity(dup ? 0.5 : 1)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                        }

                        PrimaryButton(title: fresh.count == 1 ? "Trazer 1 conta fixa" : "Trazer \(fresh.count) contas fixas",
                                      enabled: !fresh.isEmpty) {
                            store.importBills(fresh)
                            dismiss()
                            onDone()
                        }
                        Button("Escolher outro arquivo") { picking = true }
                            .textStyle(14, .semibold)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }

                    if let error {
                        Text(error).textStyle(13.5).foregroundStyle(.negative).padding(.horizontal, 4)
                    }
                }
                .foregroundStyle(.ink)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background { Backdrop() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                load(result)
            }
        }
    }

    private func load(_ result: Result<URL, Error>) {
        error = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            // Excel no Windows costuma salvar em Latin-1.
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                error = "Não consegui ler esse arquivo."
                return
            }
            rows = try SpreadsheetImport.bills(fromCSV: text)
            fileName = url.lastPathComponent
            if rows.isEmpty { error = "Não achei nenhuma conta com nome e valor nesse arquivo." }
        } catch SpreadsheetImport.Failure.missingColumns(let cols) {
            error = "Faltam colunas: \(cols.joined(separator: ", "))."
        } catch SpreadsheetImport.Failure.empty {
            error = "O arquivo está vazio."
        } catch {
            self.error = "Não consegui abrir: \(error.localizedDescription)"
        }
    }
}
