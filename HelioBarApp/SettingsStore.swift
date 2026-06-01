import Foundation

/// UserDefaults-backed prefs (cloud refresh interval).
struct SettingsStore {
    private let intervalKey = "cloudRefreshSeconds"

    var refreshSeconds: Double {
        get {
            let v = UserDefaults.standard.double(forKey: intervalKey)
            return v == 0 ? 300 : v          // default 5 min
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: intervalKey)
        }
    }
}
