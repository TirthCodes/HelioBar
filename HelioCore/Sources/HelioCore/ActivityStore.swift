import Foundation
import GRDB

/// SQLite-backed storage for activity samples.
@MainActor
public final class ActivityStore: Sendable {
    private let dbQueue: DatabaseQueue

    /// Initialize with file-based database at default location.
    public init() async throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dbURL = appSupport.appendingPathComponent("activity.db")

        try FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        dbQueue = try DatabaseQueue(path: dbURL.path)
        try await migrate()
    }

    /// Initialize with in-memory database for testing.
    public init(inMemory: Bool) async throws {
        dbQueue = try DatabaseQueue()
        try await migrate()
    }

    private func migrate() async throws {
        try await dbQueue.write { db in
            try db.create(table: "samples", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .double).notNull()
                t.column("hr", .integer).notNull()
                t.column("bundle_id", .text).notNull()
                t.column("app_name", .text).notNull()
                t.column("hr_zone", .text).notNull()
            }

            try db.create(
                index: "idx_samples_timestamp",
                on: "samples",
                columns: ["timestamp"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_samples_bundle_id",
                on: "samples",
                columns: ["bundle_id"],
                ifNotExists: true
            )
        }
    }

    /// Record a single sample.
    public func record(_ sample: ActivitySample) async {
        do {
            try await dbQueue.write { db in
                try sample.insert(db)
            }
        } catch {
            print("ActivityStore.record error: \(error)")
        }
    }

    /// Query samples in date range, ordered by timestamp.
    public func samples(from start: Date, to end: Date) async -> [ActivitySample] {
        do {
            return try await dbQueue.read { db in
                try ActivitySample
                    .filter(ActivitySample.Columns.timestamp >= start.timeIntervalSince1970)
                    .filter(ActivitySample.Columns.timestamp <= end.timeIntervalSince1970)
                    .order(ActivitySample.Columns.timestamp)
                    .fetchAll(db)
            }
        } catch {
            print("ActivityStore.samples error: \(error)")
            return []
        }
    }

    /// Delete all stored data.
    public func deleteAll() async {
        do {
            _ = try await dbQueue.write { db in
                try ActivitySample.deleteAll(db)
            }
        } catch {
            print("ActivityStore.deleteAll error: \(error)")
        }
    }

    /// Delete samples before given date.
    public func deleteBefore(_ date: Date) async {
        do {
            _ = try await dbQueue.write { db in
                try ActivitySample
                    .filter(ActivitySample.Columns.timestamp < date.timeIntervalSince1970)
                    .deleteAll(db)
            }
        } catch {
            print("ActivityStore.deleteBefore error: \(error)")
        }
    }

    /// Export samples to CSV, returns file URL.
    public func exportCSV(from start: Date, to end: Date) async -> URL? {
        let samples = await samples(from: start, to: end)
        guard !samples.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        var csv = "timestamp,hr,bundle_id,app_name,hr_zone\n"

        for s in samples {
            csv += "\(formatter.string(from: s.timestamp)),\(s.hr),\"\(s.bundleID)\",\"\(s.appName)\",\(s.hrZone.rawValue)\n"
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heliobar-export-\(Date().timeIntervalSince1970).csv")

        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("ActivityStore.exportCSV error: \(error)")
            return nil
        }
    }

    /// Total storage size in bytes.
    public var storageSizeBytes: Int64 {
        get async {
            do {
                return try await dbQueue.read { db in
                    let row = try Row.fetchOne(db, sql: "SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
                    return row?["size"] ?? 0
                }
            } catch {
                return 0
            }
        }
    }
}
