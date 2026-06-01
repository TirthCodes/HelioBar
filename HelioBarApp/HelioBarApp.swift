import SwiftUI

@main
struct HelioBarApp: App {
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: model.store) { openWindow(id: "settings") }
                .task { model.start() }
        } label: {
            Text(barTitle).foregroundStyle(zoneColor)
        }
        .menuBarExtraStyle(.window)

        Window("HelioBar Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }

    private var barTitle: String {
        model.store.liveHR.map(String.init) ?? "–"
    }

    private var zoneColor: Color {
        switch model.store.hrZone {
        case .elevated: return .orange
        case .high:     return .red
        default:        return .primary
        }
    }
}
