import AppKit
import SwiftUI
import HelioCore

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
        app.run()
    }
}

/// AppKit-driven menu bar item. NSStatusItem survives sleep/wake reliably,
/// unlike SwiftUI's MenuBarExtra (which goes unresponsive after the Mac wakes).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var titleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "–"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(store: model.store,
                                      onSettings: { [weak self] in self?.openSettings() }))

        // The menu bar title can't bind to @Observable directly, so refresh it on a timer.
        titleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTitle() }
        }
        updateTitle()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let store = model.store
        guard let hr = store.liveHR else {
            button.attributedTitle = NSAttributedString(string: "–")
            return
        }
        let arrow: String
        switch store.hrTrend {
        case .rising:  arrow = " ↑"
        case .falling: arrow = " ↓"
        default:       arrow = ""
        }
        let color: NSColor
        switch store.hrZone {
        case .elevated: color = .systemOrange
        case .high:     color = .systemRed
        default:        color = .labelColor
        }
        button.attributedTitle = NSAttributedString(
            string: "\(hr)\(arrow)",
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            ])
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "HelioBar Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
