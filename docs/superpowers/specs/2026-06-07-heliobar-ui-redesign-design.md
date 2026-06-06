# HelioBar UI Redesign — Design Spec

> Date: 2026-06-07
> Status: Approved design, pre-implementation
> Scope: Presentation-layer redesign of all UI surfaces. No changes to `HelioCore` logic.

---

## 1. Goal

Transform HelioBar's functional-but-plain menu-bar UI into a polished, coherent
**calm Apple-Fitness** experience, centered on an animated heart-rate ring. The
redesign covers **all four UI surfaces** — the menu-bar item, the popover, the
breathing view, and settings — unified by a shared design-token layer.

This is a **pure presentation-layer change**. The `HelioCore` package
(`HealthStore`, `HRZone`, alert engines, battery estimate) and the data flow in
`AppModel`/`HeartRateMonitor` are **not modified**. All views bind to the same
`HealthStore` properties they bind to today.

> **Implementation MUST use the `swiftui-expert-skill`.** All SwiftUI code in this
> redesign is written/reviewed under that skill: consult its
> `references/latest-apis.md` first (avoid deprecated APIs, use macOS 26-era
> SwiftUI), follow its state-management and view-composition guidance, apply its
> performance practices (see §9), and consult `references/liquid-glass.md` for the
> subtle material usage. Invoke the skill at the start of implementation.

### Mockup reference
`docs/mockups/popover-layouts.html` (Option A, refined) is the visual reference
for layout, color, and the menu-bar treatment.

---

## 2. Decisions (locked)

| Decision | Choice | Rationale |
|---|---|---|
| Aesthetic | Calm Apple-Fitness: dark, soft gradients, animated HR ring hero | User selection |
| Deployment target | **macOS 14 → macOS 26** | User selection; unlocks newest SwiftUI + system materials |
| Popover layout | **Option A** — hero ring + vertical stack of cards | User selection |
| Menu-bar item | Dark pill, zone-colored heart+number content, fixed width, centered number | User selection (matches reference image) |
| Trend arrow in menu bar | **Removed** (still shown in popover) | Match reference; zone color already conveys state |
| Settings | Keep native `Form`/`.grouped`, restyle for coherence | Reliability + accessibility |
| Liquid Glass | Used subtly for panel materials only; not the identity | Aesthetic is Fitness, not Glass |

---

## 3. Design system

### 3.1 New file: `HelioBarApp/Views/Theme.swift`

A namespace (`enum Theme`) of design tokens plus small color helpers. Pure,
no state, previewable. Contents:

- **Zone colors** — single source of truth for the ramp:
  - resting → `Color(red: 0.20, green: 0.78, blue: 0.35)` (≈ `#34C759`)
  - elevated → `Color(red: 1.00, green: 0.62, blue: 0.04)` (≈ `#FF9F0A`)
  - high → `Color(red: 1.00, green: 0.27, blue: 0.23)` (≈ `#FF453A`)
  - `static func color(for: HRZone) -> Color`
  - `static let ringGradient: [Color]` (green → yellow-green → orange → red) for the ring sweep.
- **Spacing** — `xs=4, sm=8, md=12, lg=16, xl=20`.
- **Radii** — `card=13, popover=22, pill=8`.
- **Typography helpers** — `bpmFont` (`.system(size:weight:.bold, design:.rounded)`, monospaced/tabular digits), `statValueFont`, `captionFont`, `cardTitleFont`.
- **Materials** — `cardBackground` (a `Color`/material + stroke), `popoverBackground`.

### 3.2 New reusable components (each in `HelioBarApp/Views/Components/`)

Each is small, single-purpose, has a `#Preview` (guarded with `#if !SWIFT_PACKAGE`),
and takes plain value inputs (no direct `HealthStore` dependency where avoidable,
so they preview in isolation).

| Component | Inputs | Renders |
|---|---|---|
| `HeartRateRing` | `bpm: Int?`, `fraction: Double` (0–1, % of max), `zone: HRZone?`, `status: SourceStatus` | Track + gradient progress arc (rounded caps, glow), center BPM + `%max · ↑` + pulsing heart. Ghosted when idle, dimmed when stale. |
| `PulsingHeart` | `bpm: Int?`, `color: Color` | SF Symbol `heart.fill` scaling subtly, animation period = `60/bpm` seconds, `.repeatForever`. Static when `bpm == nil`. |
| `HRSparkline` | `values: [Int]`, `color: Color` | Line + gradient area fill (`Canvas` or `Path`). "collecting…" when `< 2` points. |
| `StatCard` | `label: String`, `value: Int?`, `tint: Color` | Rounded card, uppercase label, tabular value, `—` when nil. |
| `ZoneBar` | `fractions: [(HRZone, Double)]`, `isEmpty: Bool` | Segmented capsule + legend. Faint when no data. |
| `BatteryPill` | `percent: Int?`, `estimateText: String?` | Drawn battery glyph (fill scales with %), `Strap NN%`, `~Xh left`. |
| `StatusBadge` | `status: SourceStatus` | `● live` / `reconnecting` / idle hint / error text. |
| `IconButton` | `systemName: String`, `tint: Color`, `action` | Square card button with an SF Symbol; used in the toolbar. |

> Note: `HRZone` and `SourceStatus` are imported from `HelioCore`; components may
> reference them but must not mutate store state.

---

## 4. Popover — `MenuContentView` rewrite

Width **300pt**, dark popover background (system material + subtle stroke),
padding `Theme.lg`. Vertical stack (`spacing: Theme.md`):

1. **`HeartRateRing`** (hero, ~176pt) — `fraction = store.percentMax/100` (clamped
   0–1), `zone = store.hrZone`, `bpm = store.liveHR`, `status = store.hrStatus`.
2. **`StatusBadge(status:)`** — the `live`/`reconnecting`/idle/error row.
3. **Sparkline card** — titled "Last 2 min", contains `HRSparkline(values: store.recent)`.
4. **Stats row** — `StatCard` ×3: min (green tint) / avg / max (red tint),
   from `store.sessionMin/sessionAvg/sessionMax`.
5. **Zone card** — titled "Time in zone", `ZoneBar` from `store.zoneFraction(_:)`
   for `[.resting, .elevated, .high]`, `isEmpty: store.zoneCounts.isEmpty`, + legend.
6. **`BatteryPill`** — `percent: store.batteryPercent`, `estimateText` derived from
   `store.batteryEstimate` (reuse existing `batteryText`/`formatRemaining` logic,
   moved into the pill or a small formatter).
7. **Toolbar** — `IconButton` ×4: breathe (`wind`, accent/blue), reset
   (`arrow.counterclockwise`), settings (`gearshape`), quit (`power`).

**Breathing toggle:** keep the existing `@State breathing` swap — when true, show
`BreathingView` in place of the stack (same mechanism as today).

**State handling (unchanged semantics):**
- `idle` → ring ghosted, badge shows "Enable Heart Rate Push", stats `—`.
- `stale` → ring + numbers dimmed (opacity), badge "reconnecting".
- `error(msg)` → badge shows the message.

---

## 5. Menu-bar item — `AppDelegate` title rendering

**Current:** `NSStatusItem` with a plain (attributed) string title updated by a 1s timer.

**New:** render the item as a **custom `NSImage`** so the dark pill + zone-colored
content is preserved (a plain template image would be forced monochrome).

- New helper `MenuBarIcon.image(bpm:zone:status:) -> NSImage`:
  - Draws a dark rounded pill (`~70×24` @ appropriate scale, fixed width) with a
    1px subtle stroke.
  - Inside: `heart.fill` SF Symbol + the BPM number, both tinted by
    `Theme.color(for: zone)`. Number uses a **tabular/monospaced** font and is
    **centered** in a fixed 3-digit slot so width never changes.
  - `stale` → content drawn gray (dimmed). `idle` → faint gray heart, **no number**.
  - Set `image.isTemplate = false` so the color renders.
- `AppDelegate`'s existing 1s timer calls this and assigns `statusItem.button?.image`
  (replacing the current title-string update). Clicking still toggles the popover.
- Fixed pixel width guarantees no horizontal shift between 2- and 3-digit values
  or across zones.

> Implementation note: render at 2× for Retina (`NSImage` with correct `size` vs
> pixel dimensions), and redraw on appearance change if needed. Keep the existing
> sleep/wake-safe `NSStatusItem` approach (do NOT switch to `MenuBarExtra` — see
> CONTEXT.md §3).

---

## 6. Breathing view — `BreathingView` restyle

Keep behavior (4s inhale/exhale timer, live HR, start/low/↓ delta, `Done` button).
Restyle visuals to match:

- Replace the blue circle with a **gradient orb** using the ring's color language
  (calm green→blue or zone-tinted), expanding to ~150pt on inhale, contracting to
  ~80pt on exhale, with a soft glow. Reserve fixed height so the popover doesn't jump.
- Guidance text ("Inhale…/Exhale…") and the live BPM use `Theme` typography.
- Reuse `PulsingHeart`/numeral styling for the live HR readout.

---

## 7. Settings view — `SettingsView` restyle

Keep the native `Form` with `.formStyle(.grouped)` and all existing `@AppStorage`
bindings and launch-at-login logic **unchanged** (reliable + accessible). Visual
alignment only:

- Add SF Symbol icons to section headers (e.g., `person`, `heart.text.square`,
  `battery.25`, `power`).
- Consistent caption styling via `Theme`.
- Optional small app header (icon + "HelioBar") at the top of the form.
- Frame stays self-managed `NSWindow` (CONTEXT.md §3 — do not switch to `Settings` scene).

---

## 8. Architecture & file changes

**New files**
- `HelioBarApp/Views/Theme.swift`
- `HelioBarApp/Views/Components/HeartRateRing.swift`
- `HelioBarApp/Views/Components/PulsingHeart.swift`
- `HelioBarApp/Views/Components/HRSparkline.swift`
- `HelioBarApp/Views/Components/StatCard.swift`
- `HelioBarApp/Views/Components/ZoneBar.swift`
- `HelioBarApp/Views/Components/BatteryPill.swift`
- `HelioBarApp/Views/Components/StatusBadge.swift`
- `HelioBarApp/Views/Components/IconButton.swift`
- `HelioBarApp/MenuBarIcon.swift` (NSImage renderer)

**Modified files**
- `HelioBarApp/Views/MenuContentView.swift` — recomposed from components.
- `HelioBarApp/Views/BreathingView.swift` — restyled.
- `HelioBarApp/Views/SettingsView.swift` — restyled.
- `HelioBarApp/HelioBarApp.swift` (`AppDelegate`) — title → `NSImage` rendering.
- `HelioBarApp/Resources/Info.plist` — `LSMinimumSystemVersion` 14.0 → 26.0.
- `project.yml` — `deploymentTarget.macOS: "26.0"`.
- `Package.swift` — `platforms: [.macOS(...)]` bump (if pinned).
- `README.md` / `docs/CONTEXT.md` — note macOS 26 minimum.

**Untouched**
- All of `HelioCore/` (logic + tests).
- `HeartRateMonitor.swift`, `AppModel.swift` data flow (only the title-rendering
  call in `AppDelegate` changes).

---

## 9. Performance (per swiftui-expert-skill)

- `PulsingHeart`: a single `.repeatForever(autoreverses:)` animation; period
  recomputed only when `bpm` changes (via `.animation(value:)` / `.onChange`), not
  every frame. No `Timer`-driven re-render of the whole view for the pulse.
- `HeartRateRing`: progress arc animates on `fraction`/`zone` change only.
- Menu-bar icon: redrawn on the existing 1s cadence (already in place); cheap
  CoreGraphics draw, no SwiftUI view tree.
- `HRSparkline`: `Canvas`-based draw, recomputed when `values` change.
- Sanity-check with Instruments only if a hitch is observed; not a blocker.

---

## 10. Testing & verification

- `HelioCore` unit tests must still pass (`cd HelioCore && swift test`) — proves
  logic untouched.
- App builds: `swift build -c release` (CLT path) and/or Xcode scheme build.
- Manual verification (per `/verify` / `run`): launch app, confirm
  popover renders in idle, live, stale states; menu-bar pill stays fixed-width
  across 2/3-digit and zone changes; breathing + settings open and function.
- SwiftUI `#Preview`s for each component (idle/live/stale where relevant) for
  fast visual iteration without launching the full app.

---

## 11. Risks & tradeoffs

- **macOS 26 minimum** drops users on macOS 14/15. CONTEXT.md §1/§4 emphasize broad
  reach for this free, non-notarized app. Accepted per user decision; README must
  state the requirement clearly.
- **Custom NSImage menu-bar item** is more code than a text title and may look
  slightly unusual (colored) next to default-gray menu-bar icons. Mitigated by the
  dark pill keeping it visually contained.
- **No data/feature changes** — this redesign does not add metrics (HRV/SpO2 etc.
  from CONTEXT.md §6 remain out of scope).

---

## 12. Out of scope

- Huami proprietary BLE protocol / rich biometrics (CONTEXT.md §6).
- Notarization, CI/release automation (CONTEXT.md §4/§7).
- Any `HelioCore` logic, zone math, or alert behavior changes.
- New features (smart alarm, history, etc.).
