import LastroKit
import SwiftUI

/// "Achei sua planilha." Enquanto o importador de planilha não existe (fase 2),
/// "Trazer as contas fixas" usa o seed do protótipo no servidor (rpc seed_demo).
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var working = false

    private let rows: [(String, String)] = [
        ("DESPESAS", "18 contas fixas"), ("Categoria", "11 categorias novas"), ("Data", "Dia de vencimento"),
        ("RECEITAS", "Salários + VR como renda"), ("Coluna OK", "Confirmado / a confirmar"), ("42 abas", "Ficam na planilha"),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.canvas.ignoresSafeArea()
            Circle().fill(Color(OKLCH(0.86, 0.10, 150))).frame(width: 420, height: 420)
                .blur(radius: 80).opacity(0.6).offset(x: 200, y: -140).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(LinearGradient(colors: [Color(OKLCH(0.62, 0.15, 150)), Color(OKLCH(0.48, 0.14, 160))],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: .rect(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color(OKLCH(0.45, 0.14, 155, alpha: 0.6)), radius: 15, y: 14)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Achei sua planilha.").textStyle(34, .bold, tracking: -0.04)
                        Text("Orçamento 2026 · 42 abas").textStyle(15).foregroundStyle(.inkSecondary)
                    }
                    Text("Você escolheu começar limpo, então trago só o que se repete. O histórico fica na planilha.")
                        .textStyle(15).foregroundStyle(.ink.opacity(0.7)).lineSpacing(3)

                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                            if i > 0 { RowDivider() }
                            HStack(spacing: 8) {
                                Text(r.0).font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.inkSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.ink.opacity(0.35))
                                Text(r.1).textStyle(14.5, .semibold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .layoutPriority(1.2)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .panel(radius: 24, fill: 0.66)

                    Button {
                        working = true
                        Task { await store.importTemplate(); working = false }
                    } label: {
                        Group {
                            if working { ProgressView().tint(.white) } else { Text("Trazer as 18 contas fixas") }
                        }
                        .textStyle(16.5, .semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.ink, in: .capsule)
                    }
                    .buttonStyle(PressScale())
                    .disabled(working)
                    .padding(.top, 4)

                    Button { store.startEmpty() } label: {
                        Text(verbatim: "Começar 100% do zero")
                            .textStyle(15.5, .semibold)
                            .foregroundStyle(.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.white.opacity(0.6), in: .capsule)
                            .overlay { Capsule().strokeBorder(.ink.opacity(0.08), lineWidth: 1) }
                    }
                    .buttonStyle(PressScale())
                }
                .foregroundStyle(.ink)
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    OnboardingView().environment(AppStore.preview())
}
