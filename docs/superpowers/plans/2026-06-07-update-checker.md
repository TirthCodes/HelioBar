# Update Checker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **REQUIRED SUB-SKILL (domain):** SwiftUI/AppKit work MUST be done under the `swiftui-expert-skill`.

**Goal:** HelioBar checks GitHub for a newer release on launch (≤1×/day) and shows a dismissible "update available" banner in the popover, with a Settings toggle + "Check now".

**Architecture:** Pure version-compare + release parsing live in `HelioCore` (unit-tested, no networking). The app's `UpdateChecker` (`@MainActor @Observable`) does the `URLSession` call, scheduling, persistence, and state; the popover shows an `UpdateBanner` and Settings gets an Updates section. One new outbound entitlement (`network.client`), disclosed in the docs.

**Tech Stack:** Swift 6 / SwiftUI / AppKit (`NSWorkspace`), `URLSession`, SwiftPM (`swift build` / `swift test`), XCTest.

**Spec:** `docs/superpowers/specs/2026-06-07-update-checker-design.md`

---

## Verification model (read first)

- **HelioCore logic is unit-tested (real TDD)** — Tasks 1–2 use XCTest in `HelioCore/Tests/`.
- **App/UI tasks** are verified by **compilation** (`swift build 2>&1 | tail -5` → `Build complete!`) plus the manual checks in the final task; SwiftUI `#Preview`s are guarded with `#if !SWIFT_PACKAGE` (repo pattern, excluded from `swift build`).
- New files under `HelioBarApp/Views/...` are auto-included by the SwiftPM `sources: ["Views"]` entry. New **top-level** app files (`HelioBarApp/UpdateChecker.swift`) must be added to `Package.swift`'s explicit `sources` list — handled in Task 4.
- Run `swift test` from the `HelioCore` directory: `cd HelioCore && swift test`.

---

## Task 1: HelioCore — version comparison

**Files:**
- Create: `HelioCore/Sources/HelioCore/UpdateCheck.swift`
- Test: `HelioCore/Tests/HelioCoreTests/UpdateCheckTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `HelioCore/Tests/HelioCoreTests/UpdateCheckTests.swift`:

```swift
import XCTest
@testable import HelioCore

final class UpdateCheckTests: XCTestCase {
    func test_newerPatch() { XCTAssertTrue(isVersion("2.0.10", newerThan: "2.0.9")) }
    func test_newerMinor() { XCTAssertTrue(isVersion("2.1.0", newerThan: "2.0.0")) }
    func test_newerMajor() { XCTAssertTrue(isVersion("3.0.0", newerThan: "2.9.9")) }
    func test_equalIsNotNewer() { XCTAssertFalse(isVersion("2.0.0", newerThan: "2.0.0")) }
    func test_olderIsNotNewer() { XCTAssertFalse(isVersion("2.0.0", newerThan: "2.1.0")) }
    func test_stripsLeadingV() { XCTAssertTrue(isVersion("v2.1.0", newerThan: "2.0.0")) }
    func test_stripsLeadingVOnCurrent() { XCTAssertFalse(isVersion("v2.0.0", newerThan: "v2.0.0")) }
    func test_shorterPadsWithZero() { XCTAssertFalse(isVersion("2.1", newerThan: "2.1.0")) }
    func test_shorterIsOlder() { XCTAssertTrue(isVersion("2.1.1", newerThan: "2.1")) }
    func test_emptyLatestIsNotNewer() { XCTAssertFalse(isVersion("", newerThan: "2.0.0")) }
    func test_garbageLatestIsNotNewer() { XCTAssertFalse(isVersion("abc", newerThan: "2.0.0")) }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd HelioCore && swift test 2>&1 | tail -15`
Expected: compile failure — `cannot find 'isVersion' in scope`.

- [ ] **Step 3: Implement `isVersion`**

Create `HelioCore/Sources/HelioCore/UpdateCheck.swift`:

```swift
import Foundation

/// Returns true if semantic version `latest` is strictly newer than `current`.
/// Strips a single leading "v"/"V", compares dot-separated integer components
/// (shorter is zero-padded). Non-numeric components compare as 0; a fully
/// unparuseable `latest` simply won't be "newer" — we never nag on garbage.
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd HelioCore && swift test 2>&1 | grep -E "UpdateCheckTests|Executed [0-9]+ test" | tail -5`
Expected: the suite runs; total executed count increased; 0 failures.

- [ ] **Step 5: Commit**

```bash
git add HelioCore/Sources/HelioCore/UpdateCheck.swift HelioCore/Tests/HelioCoreTests/UpdateCheckTests.swift
git commit -m "feat(core): add semantic version comparison for update checks"
```

---

## Task 2: HelioCore — release parsing

**Files:**
- Modify: `HelioCore/Sources/HelioCore/UpdateCheck.swift`
- Modify: `HelioCore/Tests/HelioCoreTests/UpdateCheckTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `HelioCore/Tests/HelioCoreTests/UpdateCheckTests.swift` (inside the class):

```swift
    func test_decodesLatestRelease() throws {
        let json = """
        {"tag_name":"v2.1.0","html_url":"https://github.com/TirthCodes/HelioBar/releases/tag/v2.1.0","name":"HelioBar 2.1"}
        """.data(using: .utf8)!
        let release = try JSONDecoder().decode(LatestRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v2.1.0")
        XCTAssertEqual(release.htmlURL, "https://github.com/TirthCodes/HelioBar/releases/tag/v2.1.0")
        XCTAssertEqual(release.version, "2.1.0")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd HelioCore && swift test 2>&1 | tail -15`
Expected: compile failure — `cannot find 'LatestRelease' in scope`.

- [ ] **Step 3: Implement `LatestRelease`**

Append to `HelioCore/Sources/HelioCore/UpdateCheck.swift`:

```swift
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd HelioCore && swift test 2>&1 | grep -E "Executed [0-9]+ test|failures" | tail -3`
Expected: 0 failures; total count includes the new test.

- [ ] **Step 5: Commit**

```bash
git add HelioCore/Sources/HelioCore/UpdateCheck.swift HelioCore/Tests/HelioCoreTests/UpdateCheckTests.swift
git commit -m "feat(core): add LatestRelease decoding for update checks"
```

---

## Task 3: App — UpdateChecker

**Files:**
- Create: `HelioBarApp/UpdateChecker.swift`

- [ ] **Step 1: Create `UpdateChecker.swift`**

```swift
import AppKit
import HelioCore

/// Checks GitHub for a newer release and exposes the result for the UI.
/// Lightweight: one optional outbound call to api.github.com, no telemetry.
@MainActor
@Observable
final class UpdateChecker {
    enum Status: Equatable { case idle, checking, upToDate, failed }

    private(set) var available: LatestRelease?
    private(set) var lastChecked: Date?
    private(set) var status: Status = .idle

    private let currentVersion: String
    private let session: URLSession
    private let apiURL = URL(string: "https://api.github.com/repos/TirthCodes/HelioBar/releases/latest")!
    private let releasesPageFallback = URL(string: "https://github.com/TirthCodes/HelioBar/releases/latest")!

    private let defaults = UserDefaults.standard
    private let autoKey = "autoUpdateCheck"
    private let lastCheckKey = "lastUpdateCheck"
    private let dismissedKey = "dismissedUpdateVersion"
    private let dayInterval: TimeInterval = 24 * 60 * 60

    init(session: URLSession = .shared,
         currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0") {
        self.session = session
        self.currentVersion = currentVersion
        if let t = defaults.object(forKey: lastCheckKey) as? Double {
            lastChecked = Date(timeIntervalSince1970: t)
        }
    }

    /// Auto-check entry point: respects the toggle and the 24h gate.
    func checkIfDue() async {
        let autoEnabled = (defaults.object(forKey: autoKey) as? Bool) ?? true
        guard autoEnabled else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < dayInterval { return }
        await performCheck()
    }

    /// Manual entry point: ignores the toggle and the gate.
    func checkNow() async { await performCheck() }

    func dismiss(_ release: LatestRelease) {
        defaults.set(release.version, forKey: dismissedKey)
        available = nil
    }

    func openDownload() {
        NSWorkspace.shared.open(available.flatMap { URL(string: $0.htmlURL) } ?? releasesPageFallback)
    }

    private func performCheck() async {
        status = .checking
        do {
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                status = .failed; return
            }
            let release = try JSONDecoder().decode(LatestRelease.self, from: data)
            let now = Date()
            lastChecked = now
            defaults.set(now.timeIntervalSince1970, forKey: lastCheckKey)

            let dismissed = defaults.string(forKey: dismissedKey)
            if isVersion(release.version, newerThan: currentVersion), release.version != dismissed {
                available = release
                status = .idle
            } else {
                available = nil
                status = .upToDate
            }
        } catch {
            status = .failed
        }
    }
}
```

- [ ] **Step 2: Add the file to SwiftPM sources**

In `Package.swift`, in the `HelioBar` executable target's `sources:` array, add `"UpdateChecker.swift"` after `"MenuBarIcon.swift"`:

```swift
            sources: [
                "HelioBarApp.swift",
                "AppModel.swift",
                "HeartRateMonitor.swift",
                "MenuBarIcon.swift",
                "UpdateChecker.swift",
                "Views",
            ]
```

- [ ] **Step 3: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add HelioBarApp/UpdateChecker.swift Package.swift
git commit -m "feat(app): add UpdateChecker (GitHub releases/latest, 24h gate)"
```

---

## Task 4: Network entitlement

**Files:**
- Modify: `HelioBarApp/Resources/HelioBar.entitlements`

- [ ] **Step 1: Add the outbound-network entitlement**

Replace the contents of `HelioBarApp/Resources/HelioBar.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.device.bluetooth</key><true/>
  <key>com.apple.security.network.client</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` (entitlements affect signing, not compilation; this just confirms nothing broke).

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Resources/HelioBar.entitlements
git commit -m "feat(app): allow outbound network for update checks"
```

---

## Task 5: UpdateBanner component

**Files:**
- Create: `HelioBarApp/Views/Components/UpdateBanner.swift`

- [ ] **Step 1: Create `UpdateBanner.swift`**

```swift
import SwiftUI
import HelioCore

/// "Update available" row shown at the top of the popover.
struct UpdateBanner: View {
    let release: LatestRelease
    var onDownload: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("HelioBar \(release.version) available")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Button("Download", action: onDownload)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(.blue.opacity(0.25))
        )
    }
}

#if !SWIFT_PACKAGE
#Preview {
    UpdateBanner(
        release: LatestRelease(tagName: "v2.1.0", htmlURL: "https://example.com"),
        onDownload: {}, onDismiss: {}
    )
    .frame(width: 300).padding().background(.black)
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Components/UpdateBanner.swift
git commit -m "feat(ui): add UpdateBanner component"
```

---

## Task 6: Wire UpdateChecker into AppModel + AppDelegate

**Files:**
- Modify: `HelioBarApp/AppModel.swift`
- Modify: `HelioBarApp/HelioBarApp.swift`

- [ ] **Step 1: Own + kick off the checker in `AppModel`**

In `HelioBarApp/AppModel.swift`, add the property after `let store = HealthStore()`:

```swift
    let updateChecker = UpdateChecker()
```

Then at the END of `start()` (after the `monitor = HeartRateMonitor(...)` assignment closes, before the method's closing brace), add:

```swift
        Task { await updateChecker.checkIfDue() }
```

- [ ] **Step 2: Pass the checker into both SwiftUI roots in `AppDelegate`**

In `HelioBarApp/HelioBarApp.swift`, in `applicationDidFinishLaunching`, change the popover root from:

```swift
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(store: model.store,
                                      onSettings: { [weak self] in self?.openSettings() }))
```
to:
```swift
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(store: model.store,
                                      updater: model.updateChecker,
                                      onSettings: { [weak self] in self?.openSettings() }))
```

And in `openSettings()`, change:

```swift
            window.contentViewController = NSHostingController(rootView: SettingsView())
```
to:
```swift
            window.contentViewController = NSHostingController(rootView: SettingsView(updater: model.updateChecker))
```

- [ ] **Step 3: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: FAIL — `MenuContentView` / `SettingsView` have no `updater:` parameter yet. This is expected; Tasks 7–8 add them. (If you prefer a green build at every commit, do Tasks 7 and 8 before committing this one; the three are interdependent.)

- [ ] **Step 4: Commit (after Tasks 7 & 8 build green)**

```bash
git add HelioBarApp/AppModel.swift HelioBarApp/HelioBarApp.swift
git commit -m "feat(app): own UpdateChecker and check on launch"
```

> NOTE TO IMPLEMENTER: Tasks 6, 7, 8 are mutually dependent (signature changes).
> Apply the edits for all three, run ONE `swift build` to confirm `Build complete!`,
> then make the three commits in order (6 → 7 → 8). Do not commit 6 alone expecting green.

---

## Task 7: Show the banner in the popover

**Files:**
- Modify: `HelioBarApp/Views/MenuContentView.swift`

- [ ] **Step 1: Add the `updater` parameter**

In `HelioBarApp/Views/MenuContentView.swift`, change the stored properties at the top of the struct from:

```swift
struct MenuContentView: View {
    let store: HealthStore
    var onSettings: () -> Void
    @State private var breathing = false
```
to:
```swift
struct MenuContentView: View {
    let store: HealthStore
    let updater: UpdateChecker
    var onSettings: () -> Void
    @State private var breathing = false
```

- [ ] **Step 2: Render the banner at the top of `main`**

In the `main` computed property, change the opening of the `VStack` from:

```swift
    private var main: some View {
        VStack(spacing: Theme.md) {
            HeartRateRing(
```
to:
```swift
    private var main: some View {
        VStack(spacing: Theme.md) {
            if let release = updater.available {
                UpdateBanner(
                    release: release,
                    onDownload: { updater.openDownload() },
                    onDismiss: { updater.dismiss(release) }
                )
            }
            HeartRateRing(
```

- [ ] **Step 3: Update the previews**

Replace the `#if !SWIFT_PACKAGE` preview block at the bottom of the file with:

```swift
#if !SWIFT_PACKAGE
#Preview("live") {
    let s = HealthStore()
    [62,65,70,68,72,80,95,110,90,75,72,71].forEach { s.updateHR($0) }
    return MenuContentView(store: s, updater: UpdateChecker(), onSettings: {}).background(.black)
}

#Preview("idle") {
    MenuContentView(store: HealthStore(), updater: UpdateChecker(), onSettings: {}).background(.black)
}
#endif
```

- [ ] **Step 4: Verify build (with Task 6 & 8 applied)**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add HelioBarApp/Views/MenuContentView.swift
git commit -m "feat(ui): show update banner at top of popover"
```

---

## Task 8: Settings — Updates section

**Files:**
- Modify: `HelioBarApp/Views/SettingsView.swift`

- [ ] **Step 1: Add the `updater` property + auto-check storage**

In `HelioBarApp/Views/SettingsView.swift`, add to the property declarations (next to the other `@AppStorage` lines):

```swift
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    let updater: UpdateChecker
```

- [ ] **Step 2: Add the Updates section**

In `body`, add this `Section` immediately AFTER the "Strap battery alert" section and BEFORE the "System" section:

```swift
            Section {
                Toggle("Check for updates automatically", isOn: $autoUpdateCheck)
                HStack {
                    Button("Check now") { Task { await updater.checkNow() } }
                    Spacer()
                    Text(updateStatusText).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Label("Updates", systemImage: "arrow.down.circle")
            }
```

- [ ] **Step 3: Add the status-text helper**

Add this computed property to the `SettingsView` struct (e.g. just before `setLaunch(_:)`):

```swift
    private var updateStatusText: String {
        switch updater.status {
        case .checking: return "Checking…"
        case .failed:   return "Couldn't check"
        case .upToDate: return "Up to date"
        case .idle:
            if updater.available != nil { return "Update available" }
            if let d = updater.lastChecked {
                let f = RelativeDateTimeFormatter()
                return "Checked \(f.localizedString(for: d, relativeTo: Date()))"
            }
            return ""
        }
    }
```

- [ ] **Step 4: Verify build (with Task 6 & 7 applied)**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add HelioBarApp/Views/SettingsView.swift
git commit -m "feat(ui): add Updates section to Settings"
```

---

## Task 9: Docs (Part A) — README + CONTEXT

**Files:**
- Modify: `README.md`
- Modify: `docs/CONTEXT.md`

- [ ] **Step 1: Add a latest-release badge to README**

Open `README.md`. If there is a badge row near the top (lines beginning with `![` or `[![`), append this badge to it; otherwise add it on its own line directly under the main `#` title:

```markdown
[![Latest release](https://img.shields.io/github/v/release/TirthCodes/HelioBar)](https://github.com/TirthCodes/HelioBar/releases/latest)
```

- [ ] **Step 2: Add a "What's new in 2.0" note + network disclosure**

In `README.md`, under the install/intro section (near the "📥 Just want to use it?" block if present, otherwise after the intro paragraph), add:

```markdown
### What's new in 2.0
- Redesigned, calm Apple-Fitness interface built around an animated heart-rate ring
- Strap battery tracking, low-battery alerts, and a calibrated time-remaining estimate
- Built-in update check (see below)
- Requires **macOS 26+**

See the [v2.0.0 release](https://github.com/TirthCodes/HelioBar/releases/latest) for the full changelog.

> **Network note:** From v2.0, HelioBar makes a single call to `api.github.com` to check for a
> newer release. No telemetry, no account, nothing else leaves your Mac — turn it off in
> **Settings → Updates**.
```

- [ ] **Step 3: Update CONTEXT.md entitlement + component notes**

In `docs/CONTEXT.md`:

Change the entitlements bullet from:
```
- `Resources/HelioBar.entitlements` — app-sandbox + `device.bluetooth` (network REMOVED).
```
to:
```
- `Resources/HelioBar.entitlements` — app-sandbox + `device.bluetooth` + `network.client`
  (outbound only, for the update check — see `UpdateChecker.swift`).
```

And add this bullet immediately after the `MenuBarIcon.swift` bullet:
```
- `UpdateChecker.swift` — `@MainActor @Observable`; on launch (≤1×/24h) GETs GitHub
  `releases/latest`, compares via `HelioCore.isVersion(_:newerThan:)`, and exposes
  `available` for the popover banner. Toggle `autoUpdateCheck` (default on) + manual `checkNow()`.
```

- [ ] **Step 4: Verify docs render (no build needed)**

Run: `grep -n "What's new in 2.0\|network.client\|UpdateChecker" README.md docs/CONTEXT.md | head`
Expected: matches in both files.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/CONTEXT.md
git commit -m "docs: announce 2.0, add release badge + update-check disclosure"
```

---

## Task 10: Full verification

**Files:** none (verification only)

- [ ] **Step 1: HelioCore tests (logic + no regressions)**

Run: `cd HelioCore && swift test 2>&1 | grep -E "Executed [0-9]+ test|failures|passed" | tail -3`
Expected: 0 failures; total count includes the new `UpdateCheckTests` (was 29 → now ~40).

- [ ] **Step 2: Release build**

Run: `swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Manual verification (launch)**

Run: `./scripts/install-and-run.sh`
Confirm:
- App launches; menu-bar pill + popover render as before (no regression).
- **Banner:** to force it, run once with a stubbed older version — temporarily launch with
  `defaults delete com.helio.HelioBar dismissedUpdateVersion` cleared and, for a one-off test,
  init `UpdateChecker` with `currentVersion: "0.0.1"` (revert after) → the "HelioBar X.Y available"
  banner appears at the top of the popover; **Download** opens the GitHub releases page; **✕**
  dismisses it and it stays gone on reopen.
- **Settings → Updates:** toggle present (on by default); **Check now** updates the status line
  ("Checking…" → "Up to date"/"Update available"/"Couldn't check"); turning the toggle off makes
  `checkIfDue()` a no-op on next launch.
- **Offline:** disable network → no banner, no crash, status "Couldn't check" on manual check.

- [ ] **Step 4: No commit** (verification only). If a fix was needed, commit it with a `fix(...)` message.

---

## Self-Review (completed by plan author)

**Spec coverage:**
- §3 HelioCore `isVersion` → Task 1 ✓; `LatestRelease` → Task 2 ✓ (both with tests).
- §4 `UpdateChecker` (state, keys, checkIfDue/checkNow/dismiss/openDownload, 24h gate, silent failure) → Task 3 ✓.
- §5 `UpdateBanner` → Task 5 ✓; popover banner → Task 7 ✓; Settings Updates section → Task 8 ✓.
- §6 wiring (AppModel owns + `checkIfDue()` in `start()`; AppDelegate passes `updater` to both roots) → Task 6 ✓.
- §7 `network.client` entitlement → Task 4 ✓.
- §8 Part A docs (badge, what's-new, disclosure, CONTEXT) → Task 9 ✓.
- §11 testing → Tasks 1–2 (unit) + Task 10 (build/manual) ✓.
- §2 "no OS gating" → respected (no gating code anywhere).

**Type consistency:** `UpdateChecker` exposes `available: LatestRelease?`, `status: Status`,
`lastChecked: Date?`, and methods `checkIfDue()`, `checkNow()`, `dismiss(_:)`, `openDownload()` —
used exactly so in Tasks 7 (banner) and 8 (Settings). `LatestRelease` (`tagName`, `htmlURL`,
`version`, memberwise `init`) from Task 2 is used by the checker, banner, and previews.
`isVersion(_:newerThan:)` from Task 1 is used in `performCheck()`. `MenuContentView(store:updater:onSettings:)`
and `SettingsView(updater:)` signatures match their call sites in Task 6.

**Placeholder scan:** none — every code step is complete.

**Interdependency flagged:** Tasks 6/7/8 change interlocking signatures; the plan instructs applying
all three then a single `swift build` before committing 6→7→8 in order (the lone red build in Task 6
Step 3 is called out as expected).
