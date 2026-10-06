import Testing
import Foundation
@testable import HelioCore

@Suite("ActivityStore")
struct ActivityStoreTests {

    func makeStore() async throws -> ActivityStore {
        try await ActivityStore(inMemory: true)
    }

    @Test("records and retrieves samples")
    func recordAndRetrieve() async throws {
        let store = try await makeStore()
        let now = Date()

        let sample = ActivitySample(
            timestamp: now,
            hr: 80,
            bundleID: "com.test.app",
            appName: "Test",
            hrZone: .elevated
        )

        await store.record(sample)

        let retrieved = await store.samples(
            from: now.addingTimeInterval(-60),
            to: now.addingTimeInterval(60)
        )

        #expect(retrieved.count == 1)
        #expect(retrieved[0].hr == 80)
        #expect(retrieved[0].bundleID == "com.test.app")
    }

    @Test("returns empty array for empty date range")
    func emptyRange() async throws {
        let store = try await makeStore()
        let now = Date()

        let sample = ActivitySample(
            timestamp: now,
            hr: 75,
            bundleID: "com.test",
            appName: "Test",
            hrZone: .resting
        )
        await store.record(sample)

        // Query range that excludes the sample
        let retrieved = await store.samples(
            from: now.addingTimeInterval(100),
            to: now.addingTimeInterval(200)
        )

        #expect(retrieved.isEmpty)
    }

    @Test("deleteAll removes all samples")
    func deleteAll() async throws {
        let store = try await makeStore()
        let now = Date()

        for i in 0..<5 {
            let sample = ActivitySample(
                timestamp: now.addingTimeInterval(Double(i)),
                hr: 70 + i,
                bundleID: "com.test",
                appName: "Test",
                hrZone: .resting
            )
            await store.record(sample)
        }

        await store.deleteAll()

        let retrieved = await store.samples(
            from: .distantPast,
            to: .distantFuture
        )
        #expect(retrieved.isEmpty)
    }

    @Test("deleteBefore removes old samples only")
    func deleteBefore() async throws {
        let store = try await makeStore()
        let now = Date()

        // Old sample
        await store.record(ActivitySample(
            timestamp: now.addingTimeInterval(-100),
            hr: 70,
            bundleID: "com.old",
            appName: "Old",
            hrZone: .resting
        ))

        // New sample
        await store.record(ActivitySample(
            timestamp: now,
            hr: 80,
            bundleID: "com.new",
            appName: "New",
            hrZone: .elevated
        ))

        await store.deleteBefore(now.addingTimeInterval(-50))

        let retrieved = await store.samples(from: .distantPast, to: .distantFuture)
        #expect(retrieved.count == 1)
        #expect(retrieved[0].bundleID == "com.new")
    }
}
