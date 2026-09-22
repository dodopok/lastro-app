import LastroKit
import SwiftUI

/// Tela ainda não implementada: mantém a navegação do design de pé e diz o que vem.
struct UpcomingScreen: View {
    let title: String
    let phase: String
    var pushed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if pushed {
                    Text(title).pushedTitle()
                } else {
                    Text(title).largeTitle().padding(.top, 8)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Em construção").eyebrow().foregroundStyle(Color(OKLCH(0.5, 0.2, 262)))
                    Text(phase).textStyle(15).foregroundStyle(.ink.opacity(0.7)).lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .tinted(Color(OKLCH(0.95, 0.04, 262, alpha: 0.85)))
            }
            .foregroundStyle(.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background { Backdrop() }
    }
}

extension AppTab {
    var phaseNote: String {
        switch self {
        case .hoje: ""
        case .gastos: "Lista por dia com busca e filtros (Todos, Fixos, Variáveis, Não confirmados). Fase 2."
        case .historico: "Sobra por mês em barras, acumulado do ano e maiores categorias. Fase 2."
        case .piloto: "Contas no piloto, trava de segurança e status dos pagamentos vindos do servidor. Fase 3."
        case .mais: "Recibos, cartões, dívidas, metas, contas fixas, planejar e ajustes. Fases 2 e 3."
        }
    }
}

/// Destinos empilhados a partir da Home.
struct RouteScreen: View {
    @Environment(AppStore.self) private var store
    let route: Route

    var body: some View {
        switch route {
        case .categoria(let id):
            UpcomingScreen(title: store.ledger.category(id)?.name ?? "Categoria",
                           phase: "Anel de uso, padrão do mês, ticket médio e lançamentos da categoria. Fase 2.",
                           pushed: true)
        case .cartoes:
            UpcomingScreen(title: "Cartões", phase: "Carrossel dos cartões, fatura aberta, limite e compras da fatura. Fase 2.", pushed: true)
        case .recibos:
            UpcomingScreen(title: "Recibos", phase: "\(store.ledger.pendingReceipts.count) recibos esperando confirmação. Confirmar e editar chegam na fase 2, junto com a extensão de compartilhar.", pushed: true)
        case .fixas:
            UpcomingScreen(title: "Contas fixas", phase: "\(store.ledger.activeBills.count) contas · \(BRL.format(store.ledger.billsTotal)). Criar, editar e apagar na fase 2.", pushed: true)
        case .dividas:
            UpcomingScreen(title: "Dívidas", phase: "\(BRL.format(store.ledger.openDebt)) em aberto. Fase 3.", pushed: true)
        case .metas:
            UpcomingScreen(title: "Metas e reservas", phase: "Fase 3.", pushed: true)
        case .ajustes:
            UpcomingScreen(title: "Ajustes", phase: "Fase 3.", pushed: true)
        case .planejar(let m):
            UpcomingScreen(title: "Planejar \(m.name.lowercased())",
                           phase: "Orçamento por categoria com passo de R$ 50 e itens só deste mês. Fase 2.", pushed: true)
        }
    }
}
