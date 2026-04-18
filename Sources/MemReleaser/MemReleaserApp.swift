import SwiftUI

@main
struct MemReleaserApp: App {
    @State private var store = MonitorStore()

    var body: some Scene {
        WindowGroup("MemReleaser") {
            ContentView(store: store)
        }
        .defaultSize(width: 1040, height: 760)

        MenuBarExtra("MemReleaser", systemImage: store.snapshot.level.systemImage) {
            MenuBarDashboard(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
                .frame(width: 560, height: 420)
        }
    }
}
