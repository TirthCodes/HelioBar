import Testing
import Foundation
@testable import HelioCore

@Suite("ActivitySample")
struct ActivitySampleTests {
    @Test("creates sample with all fields")
    func createSample() {
        let now = Date()
        let sample = ActivitySample(
            timestamp: now,
            hr: 85,
            bundleID: "com.apple.Safari",
            appName: "Safari",
            hrZone: .elevated
        )

        #expect(sample.timestamp == now)
        #expect(sample.hr == 85)
        #expect(sample.bundleID == "com.apple.Safari")
        #expect(sample.appName == "Safari")
        #expect(sample.hrZone == .elevated)
    }

    @Test("encodes and decodes via Codable")
    func codable() throws {
        let sample = ActivitySample(
            timestamp: Date(timeIntervalSince1970: 1000),
            hr: 72,
            bundleID: "com.test.app",
            appName: "TestApp",
            hrZone: .resting
        )

        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(ActivitySample.self, from: data)

        #expect(decoded.hr == 72)
        #expect(decoded.bundleID == "com.test.app")
        #expect(decoded.hrZone == .resting)
    }
}
