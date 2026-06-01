import XCTest
@testable import HelioCore

/// Routes responses by the `subType` query param so one client call (which makes
/// multiple requests) gets the right body for each.
private struct RoutingHTTP: HTTPFetching {
    var bodies: [String: Data]      // keyed by subType
    var status: Int = 200
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let sub = comps?.queryItems?.first { $0.name == "subType" }?.value ?? ""
        let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: nil, headerFields: nil)!
        return (bodies[sub] ?? Data(), resp)
    }
}

/// Builds a stressInfo blob containing a single IEEE 754 LE float preceded by 0x0d.
private func makeStressBlob(_ value: Float32) -> Data {
    var d = Data([0x0d])
    withUnsafeBytes(of: value.bitPattern.littleEndian) { d.append(contentsOf: $0) }
    return d
}

final class ZeppCloudClientTests: XCTestCase {
    private let creds = ZeppCredentials(appToken: "tok", host: "api.example.com")
    private let fixedNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }

    private func client(_ http: HTTPFetching) -> ZeppCloudClient {
        ZeppCloudClient(http: http, creds: creds, now: fixedNow)
    }

    // MARK: - Energy

    func test_energy_parsesPhysicalAndMentalAverage() async throws {
        let body = Data(#"""
        {"items":[{"timestamp":1,"value":{"samples":[{"physical":80,"mental":78,"minuteOfDay":600}]}}]}
        """#.utf8)
        let http = RoutingHTTP(bodies: [
            "real_data": body,
            "stress_data": Data(#"{"items":[]}"#.utf8),
            "watch_score": Data(#"{"items":[]}"#.utf8),
        ])
        let m = try await client(http).fetchMetrics()
        XCTAssertEqual(m.energy, 79)   // (80+78)/2 = 79.0
    }

    func test_energy_nilWhenItemsEmpty() async throws {
        let http = RoutingHTTP(bodies: [
            "real_data": Data(#"{"items":[]}"#.utf8),
            "stress_data": Data(#"{"items":[]}"#.utf8),
            "watch_score": Data(#"{"items":[]}"#.utf8),
        ])
        let m = try await client(http).fetchMetrics()
        XCTAssertNil(m.energy)
    }

    // MARK: - Stress (protobuf blob)

    func test_stress_decodesStressBlob() async throws {
        let blob = makeStressBlob(40.0)
        let b64 = blob.base64EncodedString()
        let stressBody = Data("""
        {"items":[{"timestamp":1,"value":{"samples":[{"stressInfo":"\(b64)","minuteOfDay":300}]}}]}
        """.utf8)
        let http = RoutingHTTP(bodies: [
            "real_data": Data(#"{"items":[]}"#.utf8),
            "stress_data": stressBody,
            "watch_score": Data(#"{"items":[]}"#.utf8),
        ])
        let m = try await client(http).fetchMetrics()
        XCTAssertEqual(m.stress, StressReading(value: 40, label: "Normal"))
    }

    // MARK: - newest sample by minuteOfDay

    func test_picksNewestSampleByMinuteOfDay() async throws {
        let body = Data(#"""
        {"items":[{"timestamp":1,"value":{"samples":[
            {"physical":60,"mental":60,"minuteOfDay":100},
            {"physical":90,"mental":90,"minuteOfDay":600}
        ]}}]}
        """#.utf8)
        let http = RoutingHTTP(bodies: [
            "real_data": body,
            "stress_data": Data(#"{"items":[]}"#.utf8),
            "watch_score": Data(#"{"items":[]}"#.utf8),
        ])
        let m = try await client(http).fetchMetrics()
        XCTAssertEqual(m.energy, 90)   // minuteOfDay 600 wins
    }

    // MARK: - Invalid token

    func test_invalidTokenBodyThrowsHttp401() async {
        let tokenBody = Data(#"{"code":0,"message":"invalid token"}"#.utf8)
        let http = RoutingHTTP(bodies: [
            "real_data": tokenBody,
            "stress_data": tokenBody,
            "watch_score": tokenBody,
        ])
        await assertThrows(client(http)) { XCTAssertEqual($0, .http(401)) }
    }

    // MARK: - makeRequest

    func test_requestCarriesAppTokenPathAndSubType() throws {
        let c = client(RoutingHTTP(bodies: [:]))
        let req = try c.makeRequest(eventType: "Charge", subType: "real_data")
        XCTAssertEqual(req.value(forHTTPHeaderField: "apptoken"), "tok")
        XCTAssertEqual(req.value(forHTTPHeaderField: "appname"), "com.huami.midong")
        XCTAssertEqual(req.url?.host, "api.example.com")
        XCTAssertEqual(req.url?.path, "/v2/users/me/events")
        let q = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(q.contains(URLQueryItem(name: "subType", value: "real_data")))
        XCTAssertTrue(q.contains(URLQueryItem(name: "eventType", value: "Charge")))
    }

    func test_makeRequestThrowsOnInvalidHost() {
        let c = ZeppCloudClient(http: RoutingHTTP(bodies: [:]),
                                creds: ZeppCredentials(appToken: "t", host: "not a host"),
                                now: fixedNow)
        XCTAssertThrowsError(try c.makeRequest(eventType: "Charge", subType: "real_data")) {
            XCTAssertEqual($0 as? ZeppCloudError, .invalidHost)
        }
    }

    // MARK: - latestStressValue unit tests

    func test_latestStressValue_parsesLastValidFloat() {
        // Two floats: 25.0 and 65.0 — should pick 65.0 (last valid ≤100)
        var d = Data([0x0d])
        withUnsafeBytes(of: Float32(25.0).bitPattern.littleEndian) { d.append(contentsOf: $0) }
        d.append(0x0d)
        withUnsafeBytes(of: Float32(65.0).bitPattern.littleEndian) { d.append(contentsOf: $0) }
        XCTAssertEqual(ZeppCloudClient.latestStressValue(d), 65)
    }

    func test_latestStressValue_ignoresValuesOver100() {
        var d = Data([0x0d])
        withUnsafeBytes(of: Float32(120.0).bitPattern.littleEndian) { d.append(contentsOf: $0) }
        XCTAssertNil(ZeppCloudClient.latestStressValue(d))
    }

    func test_latestStressValue_returnsNilOnEmptyBlob() {
        XCTAssertNil(ZeppCloudClient.latestStressValue(Data()))
    }

    // MARK: - stressLabel

    func test_stressLabelBands() {
        XCTAssertEqual(ZeppCloudClient.stressLabel(20), "Relaxed")
        XCTAssertEqual(ZeppCloudClient.stressLabel(39), "Relaxed")
        XCTAssertEqual(ZeppCloudClient.stressLabel(40), "Normal")
        XCTAssertEqual(ZeppCloudClient.stressLabel(59), "Normal")
        XCTAssertEqual(ZeppCloudClient.stressLabel(60), "Medium")
        XCTAssertEqual(ZeppCloudClient.stressLabel(79), "Medium")
        XCTAssertEqual(ZeppCloudClient.stressLabel(80), "High")
    }

    // MARK: helper

    private func assertThrows(_ client: ZeppCloudClient,
                              _ check: (ZeppCloudError) -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await client.fetchMetrics()
            XCTFail("expected throw", file: file, line: line)
        } catch let e as ZeppCloudError {
            check(e)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
