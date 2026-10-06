import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications
import HelioCore

/// Owns the BLE monitor, applies user prefs, and fires elevated-HR alerts.
@MainActor
@Observable
final class AppModel {
    nonisolated static let elevatedHRCategoryID = "elevatedHR"
    nonisolated static let breatheActionID = "breathe"

    let store = HealthStore()
    let updateChecker = UpdateChecker()
    private var monitor: HeartRateMonitor?
    private let alertEngine = ElevatedHRAlertEngine()
    private let batteryAlertEngine = BatteryAlertEngine()
    private var started = false

    private(set) var activityStore: ActivityStore?
    private var activityTracker: ActivityTracker?
    private var insightsController: InsightsWindowController?

    var isActivityTracking: Bool {
        activityTracker?.isTracking ?? false
    }

    func start() {
        guard !started else { return }
        started = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        monitor = HeartRateMonitor(
            onSample: { [weak self] sample in
                Task { @MainActor in self?.handle(bpm: sample.bpm) }
            },
            onBattery: { [weak self] percent in
                Task { @MainActor in self?.handleBattery(percent: percent) }
            },
            onConnected: { [weak self] connected in
                Task { @MainActor in if !connected { self?.store.hrDisconnected() } }
            },
            onUnavailable: { [weak self] message in
                Task { @MainActor in self?.store.hrFailed(message) }
            })
        Task { await updateChecker.checkIfDue() }

        Task {
            do {
                let actStore = try await ActivityStore()
                self.activityStore = actStore
                self.activityTracker = ActivityTracker(store: actStore, healthStore: self.store)
                self.insightsController = InsightsWindowController(store: actStore)

                if UserDefaults.standard.bool(forKey: "activityTrackingEnabled") {
                    self.activityTracker?.start()
                }

                NotificationCenter.default.addObserver(
                    forName: UserDefaults.didChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.updateTrackingState() }
                }

                NotificationCenter.default.addObserver(
                    forName: .openInsightsWindow,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.insightsController?.showWindow() }
                }

                NotificationCenter.default.addObserver(
                    forName: .deleteActivityData,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { await self?.activityStore?.deleteAll() }
                }

                NotificationCenter.default.addObserver(
                    forName: .exportActivityData,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        guard let store = self?.activityStore,
                              let tempURL = await store.exportCSV(from: .distantPast, to: Date()) else { return }
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "heliobar-activity.csv"
                        panel.allowedContentTypes = [.commaSeparatedText]
                        guard panel.runModal() == .OK, let dest = panel.url else { return }
                        try? FileManager.default.copyItem(at: tempURL, to: dest)
                    }
                }
            } catch {
                print("Failed to initialize ActivityStore: \(error)")
            }
        }
    }

    private func updateTrackingState() {
        let enabled = UserDefaults.standard.bool(forKey: "activityTrackingEnabled")
        if enabled && !(activityTracker?.isTracking ?? false) {
            activityTracker?.start()
        } else if !enabled && (activityTracker?.isTracking ?? false) {
            activityTracker?.stop()
        }
    }

    private func handle(bpm: Int) {
        applyPrefs()
        store.updateHR(bpm)
        if alertEngine.evaluate(bpm: bpm, now: Date()) { fireAlert(bpm) }
    }

    private func handleBattery(percent: Int) {
        applyPrefs()
        store.updateBattery(percent: percent)
        if batteryAlertEngine.evaluate(percent: percent) { fireBatteryAlert(percent) }
    }

    private func applyPrefs() {
        let d = UserDefaults.standard
        let age = (d.object(forKey: "age") as? Int) ?? 30
        store.maxHR = Swift.max(120, 220 - age)
        alertEngine.config = ElevatedHRConfig(
            enabled: d.bool(forKey: "alertEnabled"),
            threshold: (d.object(forKey: "alertThreshold") as? Int) ?? 100,
            duration: TimeInterval(((d.object(forKey: "alertDurationMin") as? Int) ?? 3) * 60))
        batteryAlertEngine.config = BatteryAlertConfig(
            enabled: (d.object(forKey: "batteryAlertEnabled") as? Bool) ?? true,
            threshold: (d.object(forKey: "batteryAlertThreshold") as? Int) ?? 20)
    }

    private func fireAlert(_ bpm: Int) {
        let c = UNMutableNotificationContent()
        c.title = "Heart rate elevated"
        c.body = "\(bpm) bpm for a while — time to pause."
        c.sound = .default
        c.categoryIdentifier = AppModel.elevatedHRCategoryID
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private func fireBatteryAlert(_ percent: Int) {
        let c = UNMutableNotificationContent()
        c.title = "Strap battery low"
        c.body = "Helio Strap battery is at \(percent)%."
        c.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "strap-battery-low", content: c, trigger: nil))
    }
}
