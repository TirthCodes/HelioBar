import Foundation
import HelioCore

enum ZeppTokenReader {
    /// Returns fresh Zepp credentials read from the running Zepp app's cache, or nil.
    static func current() -> ZeppCredentials? {
        guard let db = findCacheDB() else { return nil }
        let script = #"""
        DB="$1"; TMP=$(mktemp -d)
        cp "$DB" "$DB-wal" "$DB-shm" "$TMP/" 2>/dev/null
        D="$TMP/Cache.db"
        for ID in $(sqlite3 -readonly "$D" "SELECT entry_ID FROM cfurl_cache_response WHERE request_key LIKE 'https://api-mifit%' ORDER BY time_stamp DESC LIMIT 40;" 2>/dev/null); do
          sqlite3 -readonly "$D" "SELECT writefile('$TMP/r.bin', request_object) FROM cfurl_cache_blob_data WHERE entry_ID=$ID;" >/dev/null 2>&1
          TOK=$(plutil -p "$TMP/r.bin" 2>/dev/null | sed -nE 's/.*"apptoken" => "([^"]+)".*/\1/p')
          HOST=$(plutil -p "$TMP/r.bin" 2>/dev/null | sed -nE 's#.*"_CFURLString" => "https://([^/]+)/.*#\1#p' | head -1)
          if [ -n "$TOK" ] && [ -n "$HOST" ]; then printf '%s\t%s' "$TOK" "$HOST"; break; fi
        done
        rm -rf "$TMP"
        """#
        let out = runBash(script, args: [db])
        let parts = out.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        return ZeppCredentials(appToken: parts[0], host: parts[1])
    }

    private static func findCacheDB() -> String? {
        let base = ("~/Library/Containers" as NSString).expandingTildeInPath
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: base) else { return nil }
        for d in dirs {
            let p = "\(base)/\(d)/Data/Library/Caches/com.huami.watch/Cache.db"
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    private static func runBash(_ script: String, args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script, "bash"] + args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
