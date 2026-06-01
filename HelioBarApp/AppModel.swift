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

    func start() {
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
            })
    }

    func startCloudPolling() {
        pollTask?.cancel()
        guard let creds = tokenStore.load() else {
            store.cloudFailed("No Zepp token")
            return
        }
        let client = ZeppCloudClient(http: URLSession.shared, creds: creds)
        let interval = settings.refreshSeconds
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce(client)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func pollOnce(_ client: ZeppCloudClient) async {
        do {
            let m = try await client.fetchMetrics()
            store.updateCloud(stress: m.stress, readiness: m.readiness, at: Date())
        } catch {
            store.cloudFailed("\(error)")
        }
    }
}
