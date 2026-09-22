import LastroKit
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case hoje, gastos, historico, piloto, mais
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hoje: "Hoje"
        case .gastos: "Gastos"
        case .historico: "Histórico"
        case .piloto: "Piloto"
        case .mais: "Mais"
        }
    }

    var symbol: String {
        switch self {
        case .hoje: "sun.max"
        case .gastos: "list.bullet"
        case .historico: "chart.bar.xaxis"
        case .piloto: "bolt"
        case .mais: "square.grid.2x2"
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        switch store.phase {
        case .loading:
            ZStack { Backdrop(); ProgressView() }
        case .signedOut:
            SignInView()
        case .onboarding:
            OnboardingView()
        case .ready:
            MainView()
        }
    }
}

struct MainView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: AppTab = .hoje
    @State private var paths: [AppTab: NavigationPath] = [:]

    var body: some View {
        @Bindable var store = store
        ZStack(alignment: .bottom) {
            Backdrop()

            NavigationStack(path: path(for: tab)) {
                screen(for: tab)
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: Route.self) { route in
                        RouteScreen(route: route)
                    }
            }
            .id(tab)

            // Fade de leitura sob a tab bar (bottom: 130px no design)
            LinearGradient(colors: [.canvas.opacity(0), .canvas.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            BottomBar(tab: $tab) { store.open() }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .overlay(alignment: .top) { ToastView(toast: store.toast) }
        .overlay { ApprovalAlert() }
        .sheet(item: $store.launch) { draft in
            LancarSheet(draft: draft,
                        onScan: { store.show("Escanear cupom chega na próxima fase") },
                        onReceipts: { push(.recibos) })
                .presentationDetents([.large])
                .presentationCornerRadius(44)
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: tab)
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .hoje: HojeView(perform: perform)
        case .gastos: GastosView()
        case .historico: HistoricoView()
        case .piloto: PilotoView()
        case .mais: MaisView()
        }
    }

    private func path(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(get: { paths[tab] ?? NavigationPath() }, set: { paths[tab] = $0 })
    }

    private func push(_ route: Route) {
        paths[tab, default: NavigationPath()].append(route)
    }

    private func perform(_ action: HomeAction) {
        switch action {
        case .push(let route): push(route)
        case .spending(let filter):
            store.spendingFilter = filter
            tab = .gastos
        case .history: tab = .historico
        case .pilot: tab = .piloto
        }
    }
}

// MARK: - Tab bar de vidro + botão lançar

struct BottomBar: View {
    @Binding var tab: AppTab
    let onAdd: () -> Void
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases) { t in
                        Button {
                            withAnimation(.smooth(duration: 0.22)) { tab = t }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: t.symbol).font(.system(size: 19, weight: .medium))
                                Text(t.title).textStyle(10, .semibold, tracking: 0.01)
                            }
                            .foregroundStyle(t == tab ? Color.accent : Color.ink.opacity(0.72))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                if t == tab {
                                    Capsule().fill(.ink.opacity(0.07)).matchedGeometryEffect(id: "tab", in: ns)
                                }
                            }
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(t == tab ? .isSelected : [])
                    }
                }
                .padding(5)
                .frame(height: 64)
                .glassEffect(.regular.interactive(), in: .capsule)

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(PressScale(scale: 0.94))
                .glassEffect(.regular.tint(Color(Palette.accent)).interactive(), in: .circle)
                .shadow(color: Color(Palette.accentBottom).opacity(0.5), radius: 13, y: 12)
                .accessibilityLabel("Lançar gasto")
            }
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    let toast: AppStore.Toast?

    var body: some View {
        ZStack {
            if let toast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.positive, in: .circle)
                    Text(toast.message).textStyle(14, .semibold).foregroundStyle(.ink).lineLimit(1)
                }
                .padding(.leading, 14)
                .padding(.trailing, 18)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .padding(.top, 4)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: toast)
        .allowsHitTesting(false)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Autorização Face ID

struct ApprovalAlert: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let entry = store.approval.flatMap { a in store.ledger.entries.first { $0.id == a.entryId } }
        let bill = entry?.billId.flatMap { store.ledger.bill($0) }
        ZStack {
            if let a = store.approval, let entry {
                Color(red: 18 / 255, green: 20 / 255, blue: 30 / 255).opacity(0.28)
                    .ignoresSafeArea()
                    .transition(.opacity)
                VStack(spacing: 8) {
                    Image(systemName: "faceid")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(.accent)
                        .symbolEffect(.pulse, isActive: a.step == .scanning)
                        .frame(width: 58, height: 58)
                        .background(Color(Palette.accent).opacity(0.1), in: .rect(cornerRadius: 18, style: .continuous))
                        .padding(.bottom, 6)
                    Text("Autorizar Pix de \(BRL.format(entry.amountCents))").textStyle(17, .bold, tracking: -0.01)
                    Text("Para \(bill?.name.replacingOccurrences(of: "Ajuda ao ", with: "") ?? entry.description) · chave \(bill?.pixKey ?? "cadastrada")")
                        .textStyle(13.5).foregroundStyle(.ink.opacity(0.6))
                    if a.step == .scanning {
                        Text("Verificando Face ID…").textStyle(14, .semibold).foregroundStyle(.accent)
                            .frame(height: 46).padding(.top, 12)
                    } else {
                        HStack(spacing: 8) {
                            Button("Agora não") { store.cancelApproval() }
                                .buttonStyle(AlertButton(prominent: false))
                            Button("Autorizar") { Task { await store.authorize() } }
                                .buttonStyle(AlertButton(prominent: true))
                        }
                        .padding(.top, 12)
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.ink)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 18)
                .frame(width: 300)
                .glassEffect(.regular, in: .rect(cornerRadius: 34, style: .continuous))
                .transition(.scale(scale: 1.08).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.approval)
    }
}

private struct AlertButton: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(15, .semibold)
            .foregroundStyle(prominent ? Color.white : Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(prominent ? Color.accent : Color.ink.opacity(0.07), in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview {
    MainView().environment(AppStore.preview())
}
