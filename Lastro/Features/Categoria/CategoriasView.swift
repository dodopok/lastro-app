import LastroKit
import SwiftUI

/// Todas as categorias do mês em grade ("Ver todas" da Home).
struct CategoriasView: View {
    @Environment(AppStore.self) private var store
    let month: YearMonth

    var body: some View {
        let model = HomeModel(ledger: store.ledger, selected: month, today: store.today)

        Screen(title: "Categorias", subtitle: "\(month.name) · \(model.categoriesRight)") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(model.categoryCards) { card in
                    if case .push(let route) = model.action(for: card) {
                        NavigationLink(value: route) { CategoryCardView(card: card) }
                            .buttonStyle(PressScale())
                    } else {
                        CategoryCardView(card: card)
                    }
                }
            }
        }
    }
}
