import AppKit
import HelioCore

/// Checks GitHub for a newer release and exposes the result for the UI.
/// Lightweight: one optional outbound call to api.github.com, no telemetry.
@MainActor
@Observable
final class UpdateChecker {
    enum Status: Equatable { case idle, checking, upToDate, failed }

    private(set) var available: LatestRelease?
    private(set) var lastChecked: Date?
    private(set) var status: Status = .idle

    private let currentVersion: String
    private let session: URLSession
    private let apiURL = URL(string: "https://api.github.com/repos/TirthCodes/HelioBar/releases/latest")!
    private let releasesPageFallback = URL(string: "https://github.com/TirthCodes/HelioBar/releases/latest")!

    private let defaults = UserDefaults.standard
    private let autoKey = "autoUpdateCheck"
    private let lastCheckKey = "lastUpdateCheck"
    private let dismissedKey = "dismissedUpdateVersion"
    private let dayInterval: TimeInterval = 24 * 60 * 60

    init(session: URLSession = .shared,
         currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0") {
        self.session = session
        self.currentVersion = currentVersion
        if let t = defaults.object(forKey: lastCheckKey) as? Double {
            lastChecked = Date(timeIntervalSince1970: t)
        }
    }

    /// Auto-check entry point: respects the toggle and the 24h gate.
    func checkIfDue() async {
        let autoEnabled = (defaults.object(forKey: autoKey) as? Bool) ?? true
        guard autoEnabled else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < dayInterval { return }
        await performCheck()
    }

    /// Manual entry point: ignores the toggle and the gate.
    func checkNow() async { await performCheck() }

    func dismiss(_ release: LatestRelease) {
        defaults.set(release.version, forKey: dismissedKey)
        available = nil
    }

    func openDownload() {
        NSWorkspace.shared.open(available.flatMap { URL(string: $0.htmlURL) } ?? releasesPageFallback)
    }

    private func performCheck() async {
        status = .checking
        // Stamp the check time up front so a flapping network doesn't re-fire the
        // auto-check on every launch within the 24h window (even on failure).
        let now = Date()
        lastChecked = now
        defaults.set(now.timeIntervalSince1970, forKey: lastCheckKey)
        do {
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                status = .failed; return
            }
            let release = try JSONDecoder().decode(LatestRelease.self, from: data)
            let dismissed = defaults.string(forKey: dismissedKey)
            if isVersion(release.version, newerThan: currentVersion), release.version != dismissed {
                available = release
                status = .idle
            } else {
                available = nil
                status = .upToDate
            }
        } catch {
            status = .failed
        }
    }
}
