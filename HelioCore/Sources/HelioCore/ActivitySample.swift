import Foundation
import GRDB

/// A single activity sample recorded every 15 seconds.
public struct ActivitySample: Codable, Sendable, Equatable {
    public var id: Int64?
    public let timestamp: Date
    public let hr: Int
    public let bundleID: String
    public let appName: String
    public let hrZone: HRZone

    public init(
        id: Int64? = nil,
        timestamp: Date,
        hr: Int,
        bundleID: String,
        appName: String,
        hrZone: HRZone
    ) {
        self.id = id
        self.timestamp = timestamp
        self.hr = hr
        self.bundleID = bundleID
        self.appName = appName
        self.hrZone = hrZone
    }
}

// MARK: - GRDB Record

extension ActivitySample: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "samples" }

    enum Columns: String, ColumnExpression {
        case id, timestamp, hr, bundleID = "bundle_id", appName = "app_name", hrZone = "hr_zone"
    }

    public init(row: Row) {
        id = row[Columns.id]
        timestamp = Date(timeIntervalSince1970: row[Columns.timestamp])
        hr = row[Columns.hr]
        bundleID = row[Columns.bundleID]
        appName = row[Columns.appName]
        hrZone = HRZone(rawValue: row[Columns.hrZone]) ?? .resting
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.timestamp] = timestamp.timeIntervalSince1970
        container[Columns.hr] = hr
        container[Columns.bundleID] = bundleID
        container[Columns.appName] = appName
        container[Columns.hrZone] = hrZone.rawValue
    }
}
