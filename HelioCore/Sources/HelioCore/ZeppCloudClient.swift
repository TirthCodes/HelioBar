import Foundation

public protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
extension URLSession: HTTPFetching {}

public struct ZeppCredentials: Sendable, Equatable {
    public let appToken: String
    public let host: String     // e.g. "api-mifit-us3.zepp.com"
    public init(appToken: String, host: String) {
        self.appToken = appToken; self.host = host
    }
}

public enum ZeppCloudError: Error, Equatable {
    case http(Int)
    case decoding
    case invalidHost
}

public struct ZeppMetrics: Equatable, Sendable {
    public let stress: StressReading?
    public let readiness: ReadinessReading?
    public let energy: Int?
    public init(stress: StressReading?, readiness: ReadinessReading?, energy: Int?) {
        self.stress = stress; self.readiness = readiness; self.energy = energy
    }
}

/// Reads stress / readiness / energy from the Zepp/Huami event stream
/// (`/v2/users/me/events`). Endpoint shapes reverse-engineered from the live app.
/// Energy parses cleanly; stress is best-effort (decodes a protobuf float series).
public struct ZeppCloudClient: Sendable {
    private let http: HTTPFetching
    private let creds: ZeppCredentials
    private let now: @Sendable () -> Date

    public init(http: HTTPFetching, creds: ZeppCredentials,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http; self.creds = creds; self.now = now
    }

    public func fetchMetrics() async throws -> ZeppMetrics {
        let energy = try await fetchEnergy()          // primary; throws on auth/network
        let stress = (try? await fetchStress()) ?? nil      // best-effort
        let readiness = (try? await fetchReadiness()) ?? nil
        return ZeppMetrics(stress: stress, readiness: readiness, energy: energy)
    }

    func fetchEnergy() async throws -> Int? {
        guard let s = try await latestSample(eventType: "Charge", subType: "real_data"),
              let p = Self.double(s["physical"]), let m = Self.double(s["mental"])
        else { return nil }
        return Int(((p + m) / 2).rounded())
    }

    func fetchStress() async throws -> StressReading? {
        guard let s = try await latestSample(eventType: "Charge", subType: "stress_data"),
              let b64 = s["stressInfo"] as? String,
              let blob = Data(base64Encoded: b64),
              let score = Self.latestStressValue(blob)
        else { return nil }
        return StressReading(value: score, label: Self.stressLabel(score))
    }

    func fetchReadiness() async throws -> ReadinessReading? {
        guard let s = try await latestSample(eventType: "readiness", subType: "watch_score"),
              let score = Self.score(from: s) else { return nil }
        return ReadinessReading(value: score)
    }

    /// Fetches an event stream and returns the newest sample of the newest item.
    func latestSample(eventType: String, subType: String) async throws -> [String: Any]? {
        let (data, resp) = try await http.data(
            for: try makeRequest(eventType: eventType, subType: subType))
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw ZeppCloudError.http(h.statusCode)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ZeppCloudError.decoding }
        if let msg = root["message"] as? String, msg.lowercased().contains("invalid token") {
            throw ZeppCloudError.http(401)
        }
        guard let items = root["items"] as? [[String: Any]], !items.isEmpty else { return nil }
        let newest = items.max { ($0["timestamp"] as? Int ?? 0) < ($1["timestamp"] as? Int ?? 0) }!
        guard let value = newest["value"] as? [String: Any],
              let samples = value["samples"] as? [[String: Any]], !samples.isEmpty else { return nil }
        return samples.max { ($0["minuteOfDay"] as? Int ?? 0) < ($1["minuteOfDay"] as? Int ?? 0) }!
    }

    func makeRequest(eventType: String, subType: String) throws -> URLRequest {
        var comps = URLComponents()
        comps.scheme = "https"; comps.host = creds.host; comps.path = "/v2/users/me/events"
        let toMs = Int(now().timeIntervalSince1970 * 1000)
        let fromMs = toMs - 2 * 24 * 60 * 60 * 1000
        comps.queryItems = [
            .init(name: "eventType", value: eventType),
            .init(name: "subType", value: subType),
            .init(name: "from", value: String(fromMs)),
            .init(name: "to", value: String(toMs)),
            .init(name: "limit", value: "200"),
        ]
        guard let url = comps.url else { throw ZeppCloudError.invalidHost }
        var req = URLRequest(url: url)
        req.setValue(creds.appToken, forHTTPHeaderField: "apptoken")
        req.setValue("com.huami.midong", forHTTPHeaderField: "appname")
        req.setValue("ios_phone", forHTTPHeaderField: "appplatform")
        req.setValue("2.0", forHTTPHeaderField: "v")
        return req
    }

    // MARK: parsing helpers
    static func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    static func score(from sample: [String: Any]) -> Int? {
        for k in ["score", "value", "readiness", "watchScore"] {
            if let d = double(sample[k]) { return Int(d.rounded()) }
        }
        return nil
    }

    /// stressInfo is a protobuf-ish stream of `0x0d <float32-LE>` repeated.
    /// Best-effort: return the last value in (0,100]. MAY need calibration.
    static func latestStressValue(_ blob: Data) -> Int? {
        var vals: [Float] = []
        var i = blob.startIndex
        while i < blob.endIndex {
            if blob[i] == 0x0d, blob.index(i, offsetBy: 5, limitedBy: blob.endIndex) != nil {
                let f = blob.subdata(in: blob.index(after: i)..<blob.index(i, offsetBy: 5))
                    .withUnsafeBytes { $0.loadUnaligned(as: Float32.self) }
                vals.append(f)
                i = blob.index(i, offsetBy: 5)
            } else { i = blob.index(after: i) }
        }
        guard let last = vals.last(where: { $0 > 0 && $0 <= 100 }) else { return nil }
        return Int(last.rounded())
    }

    static func stressLabel(_ score: Int) -> String {
        switch score {
        case ..<40: return "Relaxed"
        case 40..<60: return "Normal"
        case 60..<80: return "Medium"
        default: return "High"
        }
    }
}
