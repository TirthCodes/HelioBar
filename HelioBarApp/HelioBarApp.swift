import AppKit
import SwiftUI
import HelioCore

@main
struct HelioBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // No SwiftUI Settings scene: its private showSettingsWindow: selector is
    // unreliable for accessory apps. The delegate manages the window directly.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// AppKit-driven menu bar item. NSStatusItem survives sleep/wake reliably,
/// unlike SwiftUI's MenuBarExtra (which goes unresponsive after the Mac wakes).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var titleTimer: Timer?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "HelioBarStatusItem"
        if let button = statusItem.button {
            button.image = MenuBarIcon.image(bpm: nil, zone: nil, status: .idle)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(store: model.store,
                                      onSettings: { [weak self] in self?.openSettings() }))

        titleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTitle() }
        }
        updateTitle()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let store = model.store
        button.image = MenuBarIcon.image(bpm: store.liveHR,
                                         zone: store.hrZone,
                                         status: store.hrStatus)
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

    /// Show our own Settings window. Reuses one instance, brings it to front
    /// reliably even though this is an .accessory (menu-bar-only) app.
    private func openSettings() {
        popover.performClose(nil)

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 330, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            window.title = "HelioBar Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }

        NSApp.setActivationPolicy(.regular)   // allow a normal, focusable window
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Back to menu-bar-only once Settings closes: no lingering Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}
