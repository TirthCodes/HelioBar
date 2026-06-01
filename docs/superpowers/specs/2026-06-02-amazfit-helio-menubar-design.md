# HelioBar — Amazfit Helio Strap menu bar app

**Date:** 2026-06-02
**Status:** Approved design, pre-implementation

## Goal

A native macOS menu bar app that shows live, glanceable health data from an
**Amazfit Helio Strap** (a screenless band synced via the Zepp app): live heart
rate always visible in the menu bar, with stress and readiness in a dropdown.

## Key constraints & realities

- Zepp has **no official Mac app and no public real-time API**.
- **HealthKit does not exist on macOS**, so reading Apple Health on a Mac is not
  an option.
- Two viable data paths for this specific device:
  - **Path B (BLE):** The Helio Strap supports **standard BLE heart-rate
    broadcast** (service `0x180D`) via the "Heart Rate Push" toggle in
    Zepp → Device → Helio Strap → Health Monitoring. This gives **true
    real-time HR** on the Mac with no auth/reverse-engineering.
  - **Path A (cloud):** The unofficial reverse-engineered Zepp/Huami web API
    gives **stress, readiness, sleep, steps**, but: (1) it is **near-live**
    only (as fresh as the last phone→cloud sync), and (2) there is **no
    password login** — an `apptoken` must be captured once from the official
    app's network traffic (HAR via HTTP Toolkit) and pasted in. Endpoints are
    reverse-engineered and may break.

**Decision:** BLE (Path B) drives the live HR number. Cloud (Path A) feeds
stress and readiness. Menu bar form factor for v1; notch HUD is a later phase.

## Stack

Native **Swift / SwiftUI**, `MenuBarExtra` (macOS 13+). CoreBluetooth for live
HR, `URLSession` for cloud. One self-contained `.app`, no sidecar processes.

## Architecture

```
┌─────────────────────────────────────────────┐
│              HealthStore (state)             │  single source of truth, @Observable
│   liveHR · stress · readiness · lastSync     │  UI binds only to this
│   + per-source status                        │
└───────▲─────────────────────────▲───────────┘
        │                         │
┌───────┴────────┐       ┌────────┴──────────┐
│ HeartRateMonitor│       │  ZeppCloudClient  │
│  (CoreBluetooth)│       │   (URLSession)    │
│  std HR 0x180D  │       │  stress/readiness │
│  ~1 Hz live     │       │  poll ~5 min      │
└────────────────┘       └───────────────────┘
        │                         │
   Helio Strap                Zepp cloud
  (BLE broadcast)          (apptoken in Keychain)
```

### Units (each one job, behind a protocol where it does I/O)

1. **`HeartRateMonitor`** — owns `CBCentralManager`. Scans for the strap
   advertising `0x180D`, connects, discovers HR Measurement characteristic
   `0x2A37`, `setNotifyValue(true)`, parses packets, publishes live BPM.
   Handles disconnect → dimmed last value + backoff reconnect.
2. **`ZeppCloudClient`** — holds the apptoken, polls stress + readiness on a
   timer, publishes latest values, stamps `lastSync`. All endpoint URLs and
   JSON parsing isolated here behind a `ZeppEndpoint` enum so breakage has one
   fix site.
3. **`HealthStore`** — `@Observable`, no I/O. Merges both sources plus
   per-source status into the state the UI reads. Directly unit-testable.
4. **`MenuBarExtra` UI** — renders live HR as the bar title (`♥ 72`,
   zone-tinted), hosts the dropdown and a Settings pane.

**Why this shape:** the two sources have different lifecycles (real-time BLE
stream vs. polling HTTP). Separating them keeps each independently testable and
ensures one source's failure can't blank the other. The UI is dumb — it only
ever reads `HealthStore`.

## Data flow

### Live HR (BLE)
1. Precondition: user enables **Heart Rate Push** in the Zepp app once.
2. On launch, `CBCentralManager` scans for `0x180D`.
3. Connect → discover `0x2A37` → `setNotifyValue(true)`.
4. Parse each notification: first byte is flags; bit 0 selects `UInt8` vs
   `UInt16` BPM. Push BPM to `HealthStore.liveHR`.
5. Disconnect → keep last value dimmed, auto-retry with backoff.
6. Fallback: if the strap ever refuses the second connection, detect
   "no BLE in N seconds" and surface that state (optionally fall back to cloud
   HR at lower frequency) — never show a frozen number as if live.

### Cloud metrics (Path A)
- Timer (default 5 min, configurable). Each tick: GET stress + readiness with
  the apptoken header, parse, update `HealthStore`, stamp `lastSync`.

## Menu bar UI

**Bar:** live HR + heart glyph, tinted by zone (resting/elevated/high): `♥ 72`.

**Dropdown:**
```
  ♥  72 bpm        ● live          BLE; green dot = streaming
 ─────────────────────────────
  Stress      34  (Relaxed)        cloud
  Readiness   81                   cloud
 ─────────────────────────────
  Last sync   2 min ago
  Settings…              Quit
```

### States (all explicitly handled)
- BLE streaming → solid number + green "live" dot.
- BLE dropped → dimmed last number + grey "reconnecting" dot.
- No HR ever → "—" + hint to enable Heart Rate Push.
- Cloud OK → values + "synced Xm ago".
- Cloud token missing/expired → values greyed + "⚠ Re-connect Zepp account"
  → Settings.

## Token & settings

- v1: **manual `apptoken` paste** + region host in Settings. Token stored in
  **Keychain**; other prefs in UserDefaults.
- Ship a short doc on capturing the token via HTTP Toolkit (HAR) once.
- Settings: token entry, cloud refresh interval, launch-at-login.
- *Later (not v1):* in-app Huami email/password login (flakier; deferred).

## Permissions / packaging

- `NSBluetoothAlwaysUsageDescription`.
- `LSUIElement = true` (menu-bar-only, no Dock icon).
- App Sandbox + Bluetooth + outgoing-network entitlements.
- Launch-at-login via `SMAppService`.

## Error handling principles

- Sources fail independently; per-source status in `HealthStore`. A dead token
  never blanks live HR; a BLE dropout never hides stress.
- All failures degrade to a **visible** state, never a silent frozen value.

## Testing strategy

- `HealthStore`: plain `@Observable`, no I/O → direct unit tests.
- `HeartRateMonitor` / `ZeppCloudClient` behind protocols; tests inject fakes
  emitting canned BPM / JSON.
- HR packet parser (flags byte, 8- vs 16-bit BPM) gets dedicated tests with
  real sample bytes.
- SwiftUI previews driven by a mock `HealthStore` in each state.

## v1 scope (YAGNI)

**In:**
- Live HR in menu bar via BLE.
- Stress + readiness in dropdown via cloud.
- Settings: token entry, refresh interval, launch-at-login.
- All degraded-state UI above.

**Out (later phases, same data layer makes them cheap):**
- Notch HUD (Phase 2).
- Sleep / steps, history, charts.
- In-app Huami login.

## Open risks

- Reverse-engineered cloud endpoints may change without notice.
- BLE second-connection behaviour of the strap is assumed-concurrent; verify on
  real hardware early.
- `apptoken` capture is a manual one-time friction point for the user.
