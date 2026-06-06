import Foundation

/// Returns true if semantic version `latest` is strictly newer than `current`.
/// Strips a single leading "v"/"V", compares dot-separated integer components
/// (shorter is zero-padded). Non-numeric components compare as 0; a fully
/// unparseable `latest` simply won't be "newer" — we never nag on garbage.
public func isVersion(_ latest: String, newerThan current: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let first = t.first, first == "v" || first == "V" { t.removeFirst() }
        return t.split(separator: ".").map { Int($0) ?? 0 }
    }
    let a = parts(latest), b = parts(current)
    let n = Swift.max(a.count, b.count)
    for i in 0..<n {
        let l = i < a.count ? a[i] : 0
        let c = i < b.count ? b[i] : 0
        if l != c { return l > c }
    }
    return false
}

/// The subset of GitHub's `releases/latest` payload we use.
public struct LatestRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    public let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    public init(tagName: String, htmlURL: String) {
        self.tagName = tagName
        self.htmlURL = htmlURL
    }

    /// Tag with a single leading "v"/"V" removed (e.g. "v2.1.0" -> "2.1.0").
    public var version: String {
        var t = tagName
        if let first = t.first, first == "v" || first == "V" { t.removeFirst() }
        return t
    }
}
