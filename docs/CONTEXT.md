# HelioBar — Project Context & Development Handoff

> Living document. Last updated: 2026-06-06.
> Purpose: capture everything needed to continue HelioBar development in a future session
> without re-deriving decisions. Read this first.

---

## 1. What HelioBar is

A native **macOS menu-bar app** that shows your **live heart rate** from an
**Amazfit Helio Strap**, read locally over Bluetooth. No account, no cloud, nothing
leaves the Mac.

- Repo: https://github.com/TirthCodes/HelioBar (public, MIT)
- Local path: `/Users/tirth/Desktop/Projects/HelioBar`, branch `main`
- Installed at: `/Applications/HelioBar.app` (also a v1.0.0 GitHub Release with a downloadable zip)
- Bundle id: `com.helio.HelioBar`, deployment target **macOS 26** (raised from 14 for the UI redesign), Swift 6 / Xcode 26

### Current feature set (all HR-only, all local)
- Live HR in the menu bar: a fixed-width dark pill with a zone-tinted (green/orange/red)
  heart + number (`♥ 84`), drawn as a custom `NSImage`. No trend arrow — trend moved to the popover ring.
- Dropdown: live **sparkline**, session **min/avg/max**, **time-in-zone** bar, **% of max HR**
- **Personalized zones** — user sets age; zones scale to estimated max HR (≈ 220 − age)
- **Elevated-HR alerts** — macOS notification when HR stays above a threshold for N minutes
- **Breathing biofeedback** — guided inhale/exhale timer, **inline in the dropdown**
- **Launch at login** (`SMAppService`), no Dock icon (`LSUIElement`), App Sandbox on

---

## 2. Architecture (how the code is laid out)

Two pieces, deliberately separated so the logic is unit-tested in isolation:

### `HelioCore/` — pure, testable Swift package (`swift test`)
- `Models.swift` — `HRZone` (resting/elevated/high, computed from **% of max HR**:
  `<0.60` resting, `0.60–0.80` elevated, `>0.80` high), `SourceStatus` (idle/live/stale/error).
- `HealthStore.swift` — `@MainActor @Observable` **single source of truth**. Holds
  `liveHR`, `hrStatus`, `maxHR`, `recent: [Int]` (sparkline, cap 150), `sessionMin/Max`,
  `zoneCounts`. Computes `hrZone`, `percentMax`, `sessionAvg`, `hrTrend`
  (enum `Trend { rising, falling, steady }`, 6-sample window ±2 bpm), `zoneFraction(_:)`.
  Methods: `updateHR`, `hrDisconnected`, `hrFailed`, `resetSession`.
- `HeartRatePacket.swift` — parses the standard BLE HR Measurement packet (`0x2A37`).
  Flags byte: bit0 = 16-bit HR, bit3 = energy-expended (skip), bit4 = RR intervals.
  **The strap sends BPM only — no RR intervals — so HRV is impossible from this path.**
- `ElevatedHRAlertEngine.swift` — `ElevatedHRConfig` + engine that fires **once per
  elevated episode** when bpm stays above threshold for the configured duration.

### `HelioBarApp/` — the macOS app target (XcodeGen-generated)
- `HelioBarApp.swift` — `@main` App with `@NSApplicationDelegateAdaptor`. **AppKit
  `NSStatusItem` + `NSPopover`** driving SwiftUI (NOT SwiftUI `MenuBarExtra` — see decisions).
  `AppDelegate` owns the status item, a 1s timer updating the menu-bar **image** (via
  `MenuBarIcon`, not an attributed-string title), and a **self-managed `NSWindow` for
  Settings** (see Settings fix below; content rect 330×400 to match `SettingsView`).
  Conforms to `NSWindowDelegate`.
- `AppModel.swift` — `@MainActor @Observable`, owns `HealthStore` + `HeartRateMonitor`
  + `ElevatedHRAlertEngine`. `start()` requests notification auth, wires BLE callbacks,
  `handle(bpm:)` → `applyPrefs()` (reads UserDefaults age→maxHR + alert config) →
  `store.updateHR` → `alertEngine.evaluate` → `fireAlert`. **Has an idempotency guard so
  `start()` only runs once** (was previously firing per menu-open).
- `HeartRateMonitor.swift` — CoreBluetooth. Standard HR service `0x180D`, characteristic
  `0x2A37`. Callbacks `onSample`/`onConnected`/`onUnavailable`. Handles all
  `CBManagerState` cases, `didFailToConnect`, `didDisconnect` (re-scan).
- `MenuBarIcon.swift` — renders the menu-bar item as a custom `NSImage` (`isTemplate = false`):
  fixed-width dark pill, zone-tinted heart + centered tabular BPM. Heart tinted via a
  `hierarchicalColor` symbol config (a template image drawn with `draw(in:)` renders black).
- `Views/Theme.swift` — shared design tokens (zone color ramp, spacing, radii, rounded
  typography, `cardSurface()` modifier). Single source of truth for the redesign's look.
- `Views/Components/` — 8 reusable views: `HeartRateRing`, `PulsingHeart`, `HRSparkline`,
  `StatCard`, `ZoneBar`, `BatteryPill`, `StatusBadge`, `IconButton`.
- `Views/MenuContentView.swift` — popover UI, redesigned (calm Apple-Fitness): hero
  `HeartRateRing`, `StatusBadge`, sparkline card, min/avg/max `StatCard`s, `ZoneBar`,
  `BatteryPill`, icon toolbar; toggles to `BreathingView` inline via `@State breathing`. Width 300.
- `Views/BreathingView.swift` — inline guided breathing, 4s inhale/exhale, live HR +
  start/low/↓ stats. Redesigned with a gradient orb.
- `Views/SettingsView.swift` — `@AppStorage` for age/alert config + Launch-at-login toggle.
  Shows launch-at-login **error messages** (from the community PR). Restyled with
  section-header SF Symbols; frame 330×400.
- `Resources/Info.plist` — `LSUIElement` true, `NSBluetoothAlwaysUsageDescription`, macOS 26 min.
- `Resources/HelioBar.entitlements` — app-sandbox + `device.bluetooth` (network REMOVED).
- Root `Package.swift` — **SwiftPM executable wrapper** (from community PR) so the app
  builds with Command Line Tools, no full Xcode.
- `project.yml` — XcodeGen config.
- `scripts/install-and-run.sh`, `scripts/uninstall.sh` — CLT build+install to `~/Applications`.

### Build commands
```bash
# Full Xcode path
xcodegen generate
xcodebuild -scheme HelioBar -configuration Release -derivedDataPath build build
cp -R build/Build/Products/Release/HelioBar.app /Applications/

# Command Line Tools path (community PR)
swift build -c release        # ~8s
./scripts/install-and-run.sh

# Logic tests
cd HelioCore && swift test
```

---

## 3. Key decisions & history (the "why", so we don't relitigate)

- **Scope: HR-only, no cloud.** Originally built with Zepp cloud integration
  (Energy/Stress/Readiness via the unofficial Huami cloud API). **User pivoted to
  "keep only HR and remove cloud."** All cloud code (`ZeppCloudClient`, `TokenStoring`,
  stress protobuf parsing, auto-token reading) was **removed**. It's in git history if needed.
- **Cloud apptoken rotates** every few minutes — a captured static token expires (401).
  We solved it by auto-reading a fresh token from the Zepp Mac app's NSURLCache, then
  removed all of it with the cloud strip. (Relevant if cloud is ever revisited.)
- **AppKit `NSStatusItem`, not SwiftUI `MenuBarExtra`.** `MenuBarExtra` goes unresponsive
  after the Mac sleeps/wakes (known bug). `NSStatusItem` survives sleep/wake reliably.
- **`@NSApplicationDelegateAdaptor`, not a custom `@main enum`** — the custom entry point
  didn't reliably run `applicationDidFinishLaunching`.
- **Settings opened via a self-managed `NSWindow`, NOT SwiftUI's `Settings` scene.**
  The private `showSettingsWindow:` selector is unreliable for accessory (menu-bar-only)
  apps on current macOS and silently did nothing. Fix: temporarily switch to `.regular`
  activation policy, show a reused `NSWindow`, revert to `.accessory` on close (so no Dock
  icon lingers). This bug recurred once; the NSWindow approach is the durable fix.
- **No HRV** — confirmed the strap broadcasts BPM only over the standard HR service
  (no RR intervals). **See §6 — this is only true for the standard path; HRV IS available
  via the proprietary protocol.**
- **Notch gotcha** — on notch MacBooks the status item can land *under* the notch
  (centered). ⌘-drag it out. (Diagnosed via a container diagnostic file; NSLog is NOT
  visible to `log show` from this sandboxed app — debugging lesson.)
- **Workflow:** user prefers **review at the end**, not after every task.

---

## 4. Distribution status & the notarization decision

- **v1.0.0 GitHub Release** exists with a downloadable `HelioBar.zip` (ad-hoc signed).
  README has a non-technical "📥 Just want to use it?" section.
- **Gatekeeper caveat:** the app is **not notarized**, so first launch shows
  "Apple cannot verify this app." Workaround: right-click → Open, or System Settings →
  Privacy & Security → "Open Anyway." This is the #1 distribution-friction point.
- **Notarization decision (current): HOLD.** Removing the warning requires the
  **Apple Developer Program ($99/YEAR — recurring, not one-time)** + Developer ID cert +
  hardened-runtime signing + `notarytool submit` + `stapler staple`. **Recommendation was
  to NOT pay yet** — it's a free app with unproven sustained demand, and the current niche
  Reddit audience will happily click past the warning. **Spend the $99 when** there's a real
  signal (actual lost users citing the warning, sustained downloads/stars, or plans for more
  Mac/iOS apps since $99 covers unlimited apps). iOS distribution would *force* the $99.
- **Two free polish items still TODO (offered, not yet done):**
  1. Add an install GIF/screenshot showing the right-click→Open step (cuts perceived friction).
  2. Add a **GitHub Action** for auto-release: push a tag → build → zip → attach to Release.
     (Can only ad-hoc sign; notarization still needs the $99.) **No CI exists yet** — there is
     no `.github/workflows/`, so merging to main does NOT auto-release.

---

## 5. Community & feedback (Reddit + the PR)

Posted on **r/AmazfitHelioStrap**. Notable threads:

- **PR #1 by @godhunter98 (Harsh M) — MERGED.** Added the SwiftPM/Command-Line-Tools build
  path (`Package.swift`, install/uninstall scripts), README split (CLT vs Xcode), preview
  guards (`#if !SWIFT_PACKAGE`), and launch-at-login **error display** in Settings. Verified
  it builds (`swift build -c release`, ~8s). **One open follow-up:** the install script
  codesigns without `--entitlements`, so the SwiftPM-installed app runs **unsandboxed**
  (Bluetooth still works via the Info.plist usage key). Ideal fix: add
  `--entitlements "$repo_root/HelioBarApp/Resources/HelioBar.entitlements"` to the codesign
  line. **This is still TODO.**
- **Feature idea — smart alarm (u/mr-zeus-):** sleep-cycle wake-up like Whoop/Fitbit.
  Verdict: a *true* sleep-stage alarm needs sleep staging (motion + HRV) → not from the
  standard BLE BPM. But an **HR-trend-based wake-in-window** heuristic IS buildable from BPM
  (HR rises toward lighter sleep). Caveat: needs HR all night → Mac near the bed + kept awake
  (power assertion). **NOTE: §6 changes this — real sleep stages ARE available via the
  proprietary protocol.**
- **Feedback — u/Deep_Ad1959:** distribution friction > features; ship notarized binary or
  Homebrew cask. Correct, and aligns with §4. (Minor correction relayed: $99 is annual, and
  notarization is more than one xcrun command.) Homebrew cask for an *unsigned* app is
  actually *more* ongoing work and still needs notarization to clear Gatekeeper — do it after
  notarizing, not instead.

---

## 6. ⭐ BIG FINDING — rich biometrics ARE available locally (proprietary BLE protocol)

This is the most important research result and **corrects an earlier wrong assumption.**
"The strap only exposes averaged BPM" is true **only for the standard BLE Heart Rate
service.** There is a **second, proprietary Huami/Zepp BLE protocol** (the one the Zepp app
itself uses) that exposes the full biometric set **locally over BLE** — no cloud needed for
the data itself.

### Two BLE paths
| | Standard HR service (HelioBar uses now) | Huami/Zepp proprietary protocol |
|---|---|---|
| Data | Averaged BPM only | HR, **HRV, SpO2, skin temp, stress, resting/max HR, respiratory rate, sleep stages, steps, battery** |
| Complexity | Trivial (`0x2A37`) | Hard — crypto handshake + proprietary decode |
| Auth | None | 16-byte auth key + ECDH handshake |
| Maturity | Rock solid | Reverse-engineered, newer, fragile |

### Reference projects (all corroborate the protocol)
- **`a9eelsh/HelioCore`** (https://github.com/a9eelsh/HelioCore) — **Swift / SwiftUI /
  CoreBluetooth, iOS+macOS, MIT** (same stack as us; same name!). Cloud login → fetch
  App Token + Auth Key → **direct BLE crypto handshake** → **live streams** HR, HRV, SpO2,
  skin temp, stress. Live-only, no history. **Best borrowable reference for our exact stack.**
- **`kevdagoat/zepp-os-esphome`** (https://github.com/kevdagoat/zepp-os-esphome) — ESP32 /
  Home Assistant, C++/Python. **Protocol goldmine:** **ECDH (sect163k1) + AES-ECB**,
  `session key = shared[8..24] XOR auth_key`; auth chars `0x0016/0x0017`, **legacy activity
  fetch `0x0004/0x0005`**; needs a 16-byte auth key from a prior Zepp pairing; exposes the
  full set incl. **sleep stages (light/deep/REM)**. ⚠️ Status: **scaffold, NOT yet flashed
  to hardware**, only cross-checked against **Gadgetbridge** source.
- **Reddit (u/ComfortableTalk9950), "Reverse-engineering the Helio strap"** — screenshot
  shows **"Direct fetch · Lookback 7.0d · 25088 samples"** + time-series → reading the strap's
  **stored history** via the legacy-fetch path. A third effort; arguably most powerful (days
  of local history, no cloud).
- **Gadgetbridge** — the canonical, years-old reverse-engineering of the Huami protocol for
  Mi Band / Amazfit. The authoritative protocol reference to consult.

### Why this matters — the real strategic fork
The earlier "Mac (BPM only) vs. mobile+HealthKit (rich data)" was a **false dichotomy.**
Third option: **keep HelioBar on Mac but switch to the Huami protocol** → get HRV, SpO2,
skin temp, stress, **and ~7 days of history**, still 100% local, no $99, no App Store, no
HealthKit. This would unlock: a *real* sleep-cycle alarm, HRV trends, stress, SpO2 — the
whole "real health companion" tier.

**Cost / risk (honest):** trades HelioBar's current biggest strength (dead-simple
reliability) for power. Requires a one-time, **fragile auth-key extraction** (same
rotating-token fragility we already hit) + a crypto handshake + proprietary byte decoding,
and the community code is new/partly unproven (esphome repo unverified on hardware).

### Alternative path — mobile (iOS) + HealthKit
Verified: the **Zepp app syncs Heart rate, Sleep, Steps, Workouts into Apple Health**
([Amazfit FAQ](https://support.amazfit.com/en/faq/3159)). On iOS you can read that **locally
via HealthKit** — the Apple-blessed gateway to rich data (sleep stages, history; HRV
*if Zepp writes it — UNVERIFIED, worth a 5-min check in the Health app*). Unlocks real
sleep-cycle alarm, HRV trends, 24/7 background, widgets/Watch complication/Live Activity,
GPS context. **Cost:** $99/yr becomes mandatory, App Store review, much more work.
Good news: **`HelioCore` (the pure logic package) ports to iOS as-is.**

---

## 7. Open decisions & suggested next steps

**Immediate, free, low-risk (good "anytime" wins):**
- [ ] Add `--entitlements` to `scripts/install-and-run.sh` codesign line (PR #1 follow-up).
- [ ] Add install GIF/screenshot to README (reduce Gatekeeper friction perception).
- [ ] Add a GitHub Action for auto-release on tag push (ad-hoc signed).

**The big directional decision (needs user call):**
- [ ] **Path A — stay simple:** keep HelioBar BPM-only, rock-solid. Add the HR-trend
      smart-alarm + polish.
- [ ] **Path B — go rich on Mac (Huami protocol):** huge capability jump (HRV/SpO2/stress/
      sleep/history), local, no $99 — but complex + fragile. **Recommended pre-work before
      committing:** (a) read `a9eelsh/HelioCore` source to judge how solid/borrowable the BLE
      handshake is; (b) pull the Gadgetbridge Huami protocol + auth-key extraction method to
      size the one-time setup and its fragility.
- [ ] **Path C — go mobile (iOS + HealthKit):** "real health companion," but forces $99 +
      App Store + most work. First do the 5-min check: does Zepp write HRV/sleep-stages to
      Apple Health on this device?
- [ ] **Notarization ($99/yr):** HOLD until a real demand signal (see §4).

**Note on the naming collision:** `a9eelsh/HelioCore` shares our package name. If we ever
borrow/collaborate or publish, consider how to disambiguate.

---

## 8. Security note
The user's Zepp `apptoken` and `userid` were only ever in terminal output / `/tmp` (cleaned
up). Before going public, all git history was scanned (`git log -p --all | grep`) for the
token/userid/apptoken patterns — **none present**. The repo contains no credentials. Keep it
that way: any future cloud or auth-key work must keep secrets out of tracked files.
