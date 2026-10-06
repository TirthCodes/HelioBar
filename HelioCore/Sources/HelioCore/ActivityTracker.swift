// HelioCore/Sources/HelioCore/ActivityTracker.swift
import Foundation
import AppKit

/// Polls the frontmost app every 15 seconds and records alongside HR.
@MainActor
public final class ActivityTracker {
    private let store: ActivityStore
    private let healthStore: HealthStore
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    public var isTracking: Bool { timer != nil }

    public init(store: ActivityStore, healthStore: HealthStore) {
        self.store = store
        self.healthStore = healthStore
    }

    /// Start 15-second polling.
    public func start() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }

        // Immediately record first sample
        tick()

        // Observe sleep/wake
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pauseForSleep() }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterWake() }
        }
    }

    /// Stop tracking.
    public func stop() {
        timer?.invalidate()
        timer = nil

        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func tick() {
        // Skip if no HR connected
        guard let hr = healthStore.liveHR else { return }

        // Get frontmost app
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return }

        let sample = ActivitySample(
            timestamp: Date(),
            hr: hr,
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            hrZone: HRZone.zone(for: hr, maxHR: healthStore.maxHR)
        )

        Task {
            await store.record(sample)
        }
    }

    private func pauseForSleep() {
        timer?.invalidate()
        timer = nil
    }

    private func resumeAfterWake() {
        guard sleepObserver != nil else { return } // Only if we were tracking

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
}
