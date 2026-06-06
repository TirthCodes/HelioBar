# HelioBar Update Checker — Design Spec

> Date: 2026-06-07
> Status: Approved design, pre-implementation
> Scope: Add an in-app "update available" check + the matching docs/disclosure.

---

## 1. Goal

HelioBar should let users know when a newer version is available. On launch (and
at most once per day) it checks the GitHub Releases API, and if a newer version
exists it shows a **dismissible banner in the popover** with a Download link.
Settings gets an **Updates** section (auto-check toggle, "Check now", status).

This also covers **Part A** (docs): a README "What's new" note, a latest-release
badge, and a one-line disclosure of the new network behaviour.

### The privacy tradeoff (decided)
HelioBar previously had **no network entitlement** ("nothing leaves the Mac").
This feature adds **one outbound call to `api.github.com`** for version info only —
no telemetry, no personal data. We add `com.apple.security.network.client`, keep
the call minimal, make it **toggleable**, and **document it**.

---

## 2. Decisions (locked)

| Decision | Choice |
|---|---|
| Privacy | Add `network.client`; disclosed, minimal, toggleable; only `api.github.com` |
| Machinery | Lightweight checker (no Sparkle / no auto-install) |
| Surface | Dismissible banner at the top of the popover |
| Cadence | On launch + at most once per 24h; manual "Check now" bypasses the gate |
| Default | Auto-check **on**, with a Settings toggle to disable |
| OS gating | **None** — the checker only ships in v2 (macOS 26+), so every user who has it can already run any future 2.x release (gating would be dead code) |

---

## 3. HelioCore additions (pure, unit-tested)

The only non-trivial logic (semver comparison, release parsing) lives in the pure
package so it is tested in isolation. **No networking in HelioCore.**

### `HelioCore/Sources/HelioCore/UpdateCheck.swift`
- `public func isVersion(_ latest: String, newerThan current: String) -> Bool`
  - Strips a single leading `v`/`V` from each.
  - Splits on `.`, compares component-wise as integers, shorter padded with 0
    (`2.1` == `2.1.0`).
  - Non-numeric / empty components → treat that comparison as not-newer; fully
    malformed `latest` → returns `false` (never nag on garbage).
  - Examples (become tests): `2.1.0 > 2.0.0` true; `2.0.0` newer than `2.0.0` false;
    `2.0.10 > 2.0.9` true; `v2.1.0` vs `2.0.0` true; `2.0.0` vs `2.1.0` false;
    `"" `/`"abc"` → false.
- `public struct LatestRelease: Decodable, Equatable, Sendable`
  - `public let tagName: String` ← `tag_name`
  - `public let htmlURL: String` ← `html_url`
  - `public var version: String` — `tagName` with a single leading `v`/`V` removed.
  - `CodingKeys` map snake_case.

### `HelioCore/Tests/HelioCoreTests/UpdateCheckTests.swift`
- Tests for every `isVersion` example above.
- One decode test: a sample GitHub `releases/latest` JSON → `LatestRelease` with
  expected `tagName`, `htmlURL`, and `version`.

---

## 4. App target: `HelioBarApp/UpdateChecker.swift`

`@MainActor @Observable final class UpdateChecker` — owns network I/O, scheduling,
state, and persistence.

**Observable state (read by the UI):**
- `private(set) var available: LatestRelease?` — set only when the fetched release
  is newer than the running version (and not the dismissed one).
- `private(set) var lastChecked: Date?`
- `private(set) var status: Status` — `enum Status { case idle, checking, upToDate, failed }`
  (drives the Settings status line; not used for the banner).

**Stored properties / constants:**
- `currentVersion: String` — from `Bundle.main.infoDictionary["CFBundleShortVersionString"]` (default `"0.0.0"`).
- `apiURL = "https://api.github.com/repos/TirthCodes/HelioBar/releases/latest"`
- `releasesPageFallback = "https://github.com/TirthCodes/HelioBar/releases/latest"`
- `urlSession: URLSession` (injectable via init for testing; defaults to `.shared`).

**UserDefaults keys (only these persist; nothing is uploaded):**
- `"autoUpdateCheck"` (Bool, default true) — the toggle.
- `"lastUpdateCheck"` (Double, time interval) — for the 24h gate.
- `"dismissedUpdateVersion"` (String) — version the user dismissed.

**Methods:**
- `func checkIfDue() async` — returns early unless `autoUpdateCheck` is true and
  (`lastUpdateCheck` is nil or > 24h ago). Then calls `performCheck()`.
- `func checkNow() async` — ignores the gate and the toggle; always `performCheck()`.
- `private func performCheck() async`:
  1. `status = .checking`.
  2. GET `apiURL` with `Accept: application/vnd.github+json`. Decode `LatestRelease`.
  3. Persist `lastUpdateCheck = now`.
  4. If `isVersion(release.version, newerThan: currentVersion)` and
     `release.version != dismissedUpdateVersion` → `available = release`,
     else `available = nil`. `status = .upToDate` when not newer.
  5. On any thrown error (offline, decode, non-200) → `status = .failed`; leave
     `available` unchanged; do **not** surface anything for auto-checks.
- `func dismiss(_ release: LatestRelease)` — sets `dismissedUpdateVersion =
  release.version` and `available = nil` (banner reappears only for a *newer* version).
- `func openDownload()` — `NSWorkspace.shared.open` the `available?.htmlURL`
  (or `releasesPageFallback`).

---

## 5. UI

### Banner — `HelioBarApp/Views/Components/UpdateBanner.swift`
- `struct UpdateBanner: View` taking `release: LatestRelease`, `onDownload: () -> Void`,
  `onDismiss: () -> Void`.
- A `cardSurface()` row, accent-tinted: arrow-down-circle icon + "HelioBar
  \(release.version) available", a **Download** button (`onDownload`), and a small
  **✕** (`onDismiss`). Uses `Theme` tokens.

### Popover — `MenuContentView`
- New parameter `let updater: UpdateChecker`.
- At the **top of `main`** (before the ring), when `updater.available` is non-nil:
  `UpdateBanner(release:…, onDownload: { updater.openDownload() }, onDismiss: { updater.dismiss(release) })`.

### Settings — `SettingsView`
- New parameter `let updater: UpdateChecker`.
- New `Section { … } header: { Label("Updates", systemImage: "arrow.down.circle") }`:
  - `Toggle("Check for updates automatically", isOn: $autoUpdateCheck)`
    (`@AppStorage("autoUpdateCheck") private var autoUpdateCheck = true`).
  - A **Check now** button → `Task { await updater.checkNow() }`.
  - A status line derived from `updater.status` / `updater.lastChecked`
    ("Checking…", "Up to date", "Update available", "Couldn't check", "Last checked …").

---

## 6. Wiring

- **`AppModel`**: add `let updateChecker = UpdateChecker()`. At the end of `start()`,
  add `Task { await updateChecker.checkIfDue() }`.
- **`AppDelegate`** (`HelioBarApp.swift`):
  - Popover root: `MenuContentView(store: model.store, updater: model.updateChecker,
    onSettings: …)`.
  - Settings window root: `SettingsView(updater: model.updateChecker)`.

---

## 7. Entitlement & privacy disclosure

- **`HelioBarApp/Resources/HelioBar.entitlements`**: add
  `<key>com.apple.security.network.client</key><true/>` (outbound only). The
  sandbox stays on; no server/listen entitlement. The install script already signs
  with this file, so no script change is needed.

---

## 8. Part A — docs (same effort)

- **`README.md`**:
  - A latest-release **badge** near the top:
    `[![Latest release](https://img.shields.io/github/v/release/TirthCodes/HelioBar)](https://github.com/TirthCodes/HelioBar/releases/latest)`.
  - A short **"What's new in 2.0"** subsection (redesign + battery + the new update
    check) linking the v2.0.0 release.
  - A one-line **network disclosure**: "From v2.0, HelioBar makes a single call to
    `api.github.com` to check for a newer release. No telemetry, nothing else leaves
    your Mac; turn it off in Settings → Updates."
- **`docs/CONTEXT.md`**: note the new `network.client` entitlement (update the
  entitlements bullet, which currently says "network REMOVED") and the update-checker
  component, so the handoff doc stays a single source of truth.

---

## 9. File changes

**New**
- `HelioCore/Sources/HelioCore/UpdateCheck.swift`
- `HelioCore/Tests/HelioCoreTests/UpdateCheckTests.swift`
- `HelioBarApp/UpdateChecker.swift`
- `HelioBarApp/Views/Components/UpdateBanner.swift`

**Modified**
- `HelioBarApp/AppModel.swift` — own + kick off the checker.
- `HelioBarApp/HelioBarApp.swift` — pass `updater` into the two SwiftUI roots.
- `HelioBarApp/Views/MenuContentView.swift` — `updater` param + banner.
- `HelioBarApp/Views/SettingsView.swift` — `updater` param + Updates section.
- `HelioBarApp/Resources/HelioBar.entitlements` — add `network.client`.
- `Package.swift` — add `"UpdateChecker.swift"` to the `HelioBar` target `sources`
  (top-level file, like `MenuBarIcon.swift`).
- `README.md`, `docs/CONTEXT.md` — Part A docs.

**Untouched**
- BLE / HR / battery logic; existing components; `MenuBarIcon`.

---

## 10. Error handling

- Auto-check failures (offline, non-200, decode error, timeout) are **silent**:
  `status = .failed`, no banner, no notification. `lastUpdateCheck` is still
  stamped so a flapping network doesn't retry every launch within 24h.
- `checkNow()` surfaces the failure via the Settings status line only ("Couldn't
  check") — never a system notification.
- GitHub's unauthenticated API rate limit (60/h per IP) is far above this usage
  (≤ ~1/day); no token needed.

---

## 11. Testing

- **HelioCore unit tests** (`swift test`): all `isVersion` cases + the
  `LatestRelease` decode test. Must keep the existing 29 tests green.
- **App build**: `swift build` / `swift build -c release`.
- **Manual verify**:
  - Temporarily run with a lower `currentVersion` (or point `apiURL` at a known
    release) → banner appears; Download opens the releases page; ✕ dismisses and
    it stays gone until a newer version.
  - Settings: toggle off → `checkIfDue()` no-ops; "Check now" still works and shows
    status; status line reflects up-to-date / failure.
  - Offline → no banner, no crash.

---

## 12. Out of scope

- Auto-download / auto-install (Sparkle) — explicitly deferred.
- Notarization / Developer ID ($99/yr) — unchanged HOLD.
- Notifying *existing v1.0.0* users in-app (impossible — v1 has no checker; handled
  out-of-band via the README/Reddit/GitHub-watch channels).
- Beta/pre-release channels; changelog rendering inside the app.
