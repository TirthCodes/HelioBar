import Foundation
import HelioCore

/// Owns the live data sources and feeds the shared HealthStore.
@MainActor
@Observable
final class AppModel {
    let store = HealthStore()
    let tokenStore: TokenStoring = KeychainTokenStore()
    let settings = SettingsStore()

    private var monitor: HeartRateMonitor?
    private var pollTask: Task<Void, Never>?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        startBLE()
        startCloudPolling()
    }

    private func startBLE() {
        monitor = HeartRateMonitor(
            onBPM: { [weak self] bpm in
                Task { @MainActor in self?.store.updateHR(bpm) }
            },
            onConnected: { [weak self] connected in
                Task { @MainActor in
                    if !connected { self?.store.hrDisconnected() }
                }
            },
            onUnavailable: { [weak self] message in
                Task { @MainActor in self?.store.hrFailed(message) }
            })
    }

    func startCloudPolling() {
        pollTask?.cancel()
        let interval = settings.refreshSeconds
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func pollOnce() async {
        guard let creds = ZeppTokenReader.current() ?? tokenStore.load() else {
            store.cloudFailed("No Zepp token (open the Zepp app)"); return
        }
        let client = ZeppCloudClient(http: URLSession.shared, creds: creds)
        do {
            let m = try await client.fetchMetrics()
            store.updateCloud(stress: m.stress, readiness: m.readiness, energy: m.energy, at: Date())
        } catch {
            store.cloudFailed("\(error)")
        }
    }
}
