import SwiftUI

/// Destinos empilhados.
struct RouteScreen: View {
    let route: Route

    var body: some View {
        switch route {
        case .categoria(let id): CategoriaView(categoryId: id)
        case .cartoes: CartoesView()
        case .recibos: RecibosView()
        case .fixas: FixasView()
        case .dividas: DividasView()
        case .metas: MetasView()
        case .ajustes: AjustesView()
        case .planejar(let m): PlanejarView(month: m)
        }
    }
}
