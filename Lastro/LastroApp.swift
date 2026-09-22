import SwiftUI

@main
struct LastroApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(.accent)
                .preferredColorScheme(.light)
                .task {
                    await store.start()
                    store.drainInbox()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    store.drainInbox()
                    Task { await store.refresh() }
                }
        }
    }
}
