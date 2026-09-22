import LastroKit
import PhotosUI
import SwiftUI
import VisionKit

/// Escanear cupom: Live Text da câmera (aparelho) ou foto da galeria (simulador).
struct ScanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var parsed: ParsedReceipt?
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var failed = false

    private var live: Bool { LiveTextScanner.isAvailable }

    var body: some View {
        ZStack {
            Color(hex: 0x0B0C0F).ignoresSafeArea()
            if live {
                LiveTextScanner { lines in update(ReceiptParser.parse(lines: lines)) }
                    .ignoresSafeArea()
            } else {
                placeholder
            }
            frameCorners.allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let amount = parsed?.amount {
                    Label("\(BRL.format(amount)) detectado", systemImage: "checkmark")
                        .textStyle(15, .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 38)
                        .background(Color(OKLCH(0.62, 0.15, 155)), in: .capsule)
                        .shadow(color: Color(OKLCH(0.5, 0.15, 155, alpha: 0.7)), radius: 12, y: 10)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .padding(.bottom, 16)
                }
                bottomCard
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: parsed)
        .sensoryFeedback(.success, trigger: parsed?.amount) { old, new in old == nil && new != nil }
        .onChange(of: photo) { _, item in Task { await read(item) } }
    }

    // MARK: partes

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44).contentShape(.circle)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Fechar")
            Spacer()
            Text("Escanear cupom").textStyle(16, .semibold)
            Spacer()
            PhotosPicker(selection: $photo, matching: .images) {
                Image(systemName: "photo").font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44).contentShape(.circle)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Escolher foto do cupom")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    /// Sem câmera (simulador): o espaço do design + escolher foto.
    private var placeholder: some View {
        ZStack {
            Canvas { ctx, size in
                var x: CGFloat = -size.height
                while x < size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    ctx.stroke(p, with: .color(.white.opacity(0.03)), lineWidth: 14)
                    x += 28
                }
            }
            .ignoresSafeArea()
            VStack(spacing: 14) {
                if reading {
                    ProgressView().tint(.white)
                    Text("Lendo o cupom…").textStyle(13, .medium)
                } else {
                    Text("Câmera indisponível aqui").textStyle(13, .medium)
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Escolher foto do cupom", systemImage: "photo")
                            .textStyle(14, .semibold)
                            .padding(.horizontal, 16).frame(height: 40)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
            }
            .foregroundStyle(.white.opacity(0.7))
            .offset(y: -80)
        }
    }

    private var frameCorners: some View {
        GeometryReader { geo in
            let w: CGFloat = 260, h: CGFloat = 370
            let rect = CGRect(x: (geo.size.width - w) / 2, y: 130, width: w, height: h)
            Path { p in
                let l: CGFloat = 36, r: CGFloat = 14
                // cantos com raio, como no design
                p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
                p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
                p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
                p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
                p.move(to: CGPoint(x: rect.minX, y: rect.maxY - l))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
                p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX + l, y: rect.maxY))
                p.move(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
                p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r), control: CGPoint(x: rect.maxX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    @ViewBuilder
    private var bottomCard: some View {
        let category = suggestedCategory
        VStack(alignment: .leading, spacing: 14) {
            if let parsed, let amount = parsed.amount {
                HStack(spacing: 12) {
                    if let category { CategoryIcon(category, size: 44, radius: 14) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(parsed.merchant ?? "Cupom").textStyle(17, .bold).lineLimit(1)
                        Text("hoje · \(Date.now.formatted(date: .omitted, time: .shortened)) · Pix/débito")
                            .textStyle(13).foregroundStyle(.inkSecondary)
                    }
                    Spacer()
                    Text(BRL.format(amount)).textStyle(20, .bold, tracking: -0.02).monospacedDigit()
                }
                if let category {
                    HStack(spacing: 8) {
                        Text("Categoria sugerida").textStyle(13).foregroundStyle(.inkSecondary)
                        Text(category.name).textStyle(13, .semibold)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(Color.categoryTint(category.hue, 0.18), in: .capsule)
                    }
                }
                HStack(spacing: 8) {
                    PrimaryButton(title: "Salvar gasto") { save(parsed, amount: amount, category: category) }
                    Button { edit(parsed, amount: amount, category: category) } label: {
                        Text("Editar").textStyle(15, .semibold)
                            .padding(.horizontal, 20).frame(height: 54)
                            .background(.ink.opacity(0.07), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(PressScale())
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(failed ? "Não achei o total nesse cupom" : "Aponte para o cupom")
                        .textStyle(17, .bold)
                    Text(failed ? "Tente uma foto mais reta e com o TOTAL visível, ou lance à mão."
                         : "Eu leio o total, o nome da loja e sugiro a categoria.")
                        .textStyle(13.5).foregroundStyle(.inkSecondary)
                }
                Button { dismiss(); store.openLauncher(after: .milliseconds(350)) } label: {
                    Text("Lançar à mão").textStyle(15, .semibold)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(.ink.opacity(0.07), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(PressScale())
            }
        }
        .foregroundStyle(.ink)
        .environment(\.colorScheme, .light)
        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 26)
        .background(.white.opacity(0.86), in: .rect(cornerRadius: 44, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 44, style: .continuous))
    }

    // MARK: lógica

    private var suggestedCategory: BudgetCategory? {
        let cats = store.ledger.activeCategories
        return parsed?.categorySlug.flatMap { slug in cats.first { $0.slug == slug } }
            ?? cats.first { $0.nature == .variavel }
    }

    private func update(_ p: ParsedReceipt) {
        // Só troca quando achou valor: evita o card piscar a cada quadro.
        guard p.amount != nil, p != parsed else { return }
        parsed = p
        failed = false
    }

    private func read(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        reading = true
        defer { reading = false; photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let lines = try? await TextRecognizer.lines(in: data) else {
            failed = true
            return
        }
        let p = ReceiptParser.parse(lines: lines)
        if p.amount == nil { failed = true } else { parsed = p }
    }

    private func save(_ p: ParsedReceipt, amount: Money, category: BudgetCategory?) {
        guard let category else { return }
        store.addExpense(amount: amount, categoryId: category.id, cardId: nil,
                         description: p.merchant, source: .scan)
        dismiss()
    }

    private func edit(_ p: ParsedReceipt, amount: Money, category: BudgetCategory?) {
        dismiss()
        store.openLauncher(LaunchDraft(amount: amount, categoryId: category?.id, description: p.merchant),
                           after: .milliseconds(350))
    }
}

/// Câmera com Live Text (VisionKit). Entrega as linhas lidas de cima para baixo.
struct LiveTextScanner: UIViewControllerRepresentable {
    let onLines: ([String]) -> Void

    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["pt-BR"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLines: onLines) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onLines: ([String]) -> Void
        private var last = Date.distantPast

        init(onLines: @escaping ([String]) -> Void) { self.onLines = onLines }

        func dataScanner(_ s: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) { emit(allItems) }
        func dataScanner(_ s: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) { emit(allItems) }
        func dataScanner(_ s: DataScannerViewController, didRemove removed: [RecognizedItem], allItems: [RecognizedItem]) { emit(allItems) }

        private func emit(_ items: [RecognizedItem]) {
            // No máximo ~3 leituras por segundo.
            guard Date.now.timeIntervalSince(last) > 0.3 else { return }
            last = .now
            let lines = items.compactMap { item -> (CGFloat, CGFloat, String)? in
                guard case .text(let t) = item else { return nil }
                return (t.bounds.topLeft.y, t.bounds.topLeft.x, t.transcript)
            }
            .sorted { abs($0.0 - $1.0) > 8 ? $0.0 < $1.0 : $0.1 < $1.1 }
            .map(\.2)
            onLines(lines)
        }
    }
}
