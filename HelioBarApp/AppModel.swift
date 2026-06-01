import Foundation
import HelioCore

/// Owns the BLE heart-rate monitor and feeds the shared HealthStore.
@MainActor
@Observable
final class AppModel {
    let store = HealthStore()
    private var monitor: HeartRateMonitor?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor = HeartRateMonitor(
            onBPM: { [weak self] bpm in
                Task { @MainActor in self?.store.updateHR(bpm) }
            },
            onConnected: { [weak self] connected in
                Task { @MainActor in if !connected { self?.store.hrDisconnected() } }
            },
            onUnavailable: { [weak self] message in
                Task { @MainActor in self?.store.hrFailed(message) }
            })
    }
}
