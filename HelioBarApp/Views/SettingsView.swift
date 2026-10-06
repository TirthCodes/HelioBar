import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("age") private var age = 30
    @AppStorage("alertEnabled") private var alertEnabled = false
    @AppStorage("alertThreshold") private var alertThreshold = 100
    @AppStorage("alertDurationMin") private var alertDurationMin = 3
    @AppStorage("batteryAlertEnabled") private var batteryAlertEnabled = true
    @AppStorage("batteryAlertThreshold") private var batteryAlertThreshold = 20
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    let updater: UpdateChecker
    @AppStorage("activityTrackingEnabled") private var activityTrackingEnabled = false
    @State private var storageSizeText = "Calculating..."
    @State private var showDeleteConfirmation = false
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Stepper("Age: \(age)", value: $age, in: 10...100)
                Text("Max HR ≈ \(220 - age) bpm · zones scale to this")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Label("You", systemImage: "person.fill")
            }
            Section {
                Toggle("Notify when HR stays high", isOn: $alertEnabled)
                Stepper("Above \(alertThreshold) bpm", value: $alertThreshold, in: 80...200, step: 5)
                Stepper("For \(alertDurationMin) min", value: $alertDurationMin, in: 1...30)
            } header: {
                Label("Elevated-HR alert", systemImage: "heart.text.square.fill")
            }
            Section {
                Toggle("Notify when strap battery is low", isOn: $batteryAlertEnabled)
                Stepper("At or below \(batteryAlertThreshold)%", value: $batteryAlertThreshold, in: 5...50, step: 5)
            } header: {
                Label("Strap battery alert", systemImage: "battery.25percent")
            }
            Section {
                Toggle("Check for updates automatically", isOn: $autoUpdateCheck)
                HStack {
                    Button("Check now") { Task { await updater.checkNow() } }
                    Spacer()
                    Text(updateStatusText).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Label("Updates", systemImage: "arrow.down.circle")
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
                if let launchAtLoginError {
                    Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Label("System", systemImage: "power")
            }
            Section {
                Toggle("Track app activity", isOn: $activityTrackingEnabled)
                Text("Records which app is active alongside your heart rate")
                    .font(.caption).foregroundStyle(.secondary)

                if activityTrackingEnabled {
                    HStack {
                        Text("Data stored")
                        Spacer()
                        Text(storageSizeText)
                            .foregroundStyle(.secondary)
                    }

                    Button("View Insights") {
                        NotificationCenter.default.post(name: .openInsightsWindow, object: nil)
                    }

                    Button("Export All Data...") {
                        NotificationCenter.default.post(name: .exportActivityData, object: nil)
                    }

                    Button("Delete All Data...", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .confirmationDialog("Delete all activity data?", isPresented: $showDeleteConfirmation) {
                        Button("Delete", role: .destructive) {
                            NotificationCenter.default.post(name: .deleteActivityData, object: nil)
                        }
                    } message: {
                        Text("This cannot be undone.")
                    }
                }
            } header: {
                Label("Activity Tracking", systemImage: "chart.bar.fill")
            }
        }
        .formStyle(.grouped)
        .frame(width: 330, height: 400)
    }

    private var updateStatusText: String {
        switch updater.status {
        case .checking: return "Checking…"
        case .failed:   return "Couldn't check"
        case .upToDate: return "Up to date"
        case .idle:
            if updater.available != nil { return "Update available" }
            if let d = updater.lastChecked {
                let f = RelativeDateTimeFormatter()
                return "Checked \(f.localizedString(for: d, relativeTo: Date()))"
            }
            return ""
        }
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            launchAtLoginError = error.localizedDescription
        }
    }
}

extension Notification.Name {
    static let openInsightsWindow = Notification.Name("openInsightsWindow")
    static let exportActivityData = Notification.Name("exportActivityData")
    static let deleteActivityData = Notification.Name("deleteActivityData")
    static let startBreathing = Notification.Name("startBreathing")
}
