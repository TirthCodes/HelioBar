import SwiftUI

@main
struct HelioBarApp: App {
    var body: some Scene {
        MenuBarExtra("HelioBar", systemImage: "heart.fill") {
            Text("Hello from HelioBar")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
