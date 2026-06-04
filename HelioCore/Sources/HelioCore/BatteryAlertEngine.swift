import Foundation

/// Config for the low strap-battery alert.
public struct BatteryAlertConfig: Equatable, Sendable {
    public var enabled: Bool
    public var threshold: Int

    public init(enabled: Bool = true, threshold: Int = 20) {
        self.enabled = enabled
        self.threshold = threshold
    }
}

/// Fires once when battery is at/below threshold, then re-arms after recovery.
public final class BatteryAlertEngine {
    public var config: BatteryAlertConfig
    private var fired = false

    public init(config: BatteryAlertConfig = .init()) {
        self.config = config
    }

    public func evaluate(percent: Int) -> Bool {
        guard config.enabled else {
            fired = false
            return false
        }

        let threshold = Swift.min(100, Swift.max(0, config.threshold))
        if percent <= threshold {
            guard !fired else { return false }
            fired = true
            return true
        }

        fired = false
        return false
    }
}
