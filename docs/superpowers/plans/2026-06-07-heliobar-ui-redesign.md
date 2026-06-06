# HelioBar UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **REQUIRED SUB-SKILL (domain):** All SwiftUI work in this plan MUST be done under the `swiftui-expert-skill` — consult its `references/latest-apis.md` before writing views, follow its state-management/performance guidance, and `references/liquid-glass.md` for material usage.

**Goal:** Redesign all of HelioBar's UI (menu-bar item, popover, breathing, settings) into a calm Apple-Fitness look built around an animated heart-rate ring, on macOS 26.

**Architecture:** Pure presentation-layer change. A new `Theme.swift` token layer + 8 small reusable SwiftUI components feed a recomposed `MenuContentView`. The menu-bar item becomes a custom `NSImage`. `HelioCore` logic and the `AppModel`/`HeartRateMonitor` data flow are untouched.

**Tech Stack:** SwiftUI (macOS 26), AppKit (`NSStatusItem`, `NSImage`, CoreGraphics for the menu-bar icon), SwiftPM (`swift build`) + XcodeGen.

**Spec:** `docs/superpowers/specs/2026-06-07-heliobar-ui-redesign-design.md`
**Visual reference:** `docs/mockups/popover-layouts.html`

---

## Verification model (read first)

This is a UI redesign; most tasks are verified by **compilation + isolated SwiftUI preview**, not unit tests (`HelioCore` already has the logic tests, which must stay green).

- **Compile check (every task):** `swift build 2>&1 | tail -5` → expect `Build complete!`
- **Preview:** each component has a `#Preview` guarded by `#if !SWIFT_PACKAGE` (the existing repo pattern — previews are Xcode-only and excluded from `swift build`). Open the file in Xcode to view; not required for the plan to proceed.
- **Logic tests unchanged:** `cd HelioCore && swift test` → expect all pass (run once at the end).
- **Final manual verification:** launch the app and check live/idle/stale states.

New files live under `HelioBarApp/Views/` and `HelioBarApp/Views/Components/` (auto-included by both XcodeGen and the SwiftPM `sources: ["Views"]` entry). The one new **top-level** file (`HelioBarApp/MenuBarIcon.swift`) must be added to `Package.swift`'s explicit `sources` list — handled in Task 14.

---

## Task 1: Bump deployment target to macOS 26

**Files:**
- Modify: `project.yml:4-5`
- Modify: `Package.swift:6`
- Modify: `HelioBarApp/Resources/Info.plist:10`

- [ ] **Step 1: Bump XcodeGen target**

In `project.yml`, change:
```yaml
  deploymentTarget:
    macOS: "14.0"
```
to:
```yaml
  deploymentTarget:
    macOS: "26.0"
```

- [ ] **Step 2: Bump SwiftPM platform**

In `Package.swift`, change `platforms: [.macOS(.v14)],` to `platforms: [.macOS(.v26)],`

- [ ] **Step 3: Bump Info.plist minimum**

In `HelioBarApp/Resources/Info.plist`, change `<key>LSMinimumSystemVersion</key><string>14.0</string>` to `<key>LSMinimumSystemVersion</key><string>26.0</string>`

- [ ] **Step 4: Verify the existing app still builds at the new target**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add project.yml Package.swift HelioBarApp/Resources/Info.plist
git commit -m "build: raise deployment target to macOS 26"
```

---

## Task 2: Theme token layer

**Files:**
- Create: `HelioBarApp/Views/Theme.swift`

- [ ] **Step 1: Create `Theme.swift`**

```swift
import SwiftUI
import HelioCore

/// Design tokens for the HelioBar UI. Single source of truth for color,
/// spacing, radii, and typography across every surface.
enum Theme {
    // Zone color ramp
    static let resting  = Color(red: 0.20, green: 0.78, blue: 0.35) // #34C759
    static let elevated = Color(red: 1.00, green: 0.62, blue: 0.04) // #FF9F0A
    static let high     = Color(red: 1.00, green: 0.27, blue: 0.23) // #FF453A

    static func color(for zone: HRZone?) -> Color {
        switch zone {
        case .resting:  return resting
        case .elevated: return elevated
        case .high:     return high
        case nil:       return .secondary
        }
    }

    /// Gradient sweep used by the HR ring (green → yellow-green → orange → red).
    static let ringGradient: [Color] = [
        resting,
        Color(red: 0.62, green: 0.82, blue: 0.29),
        elevated,
        high,
    ]

    // Spacing
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20

    // Radii
    static let cardRadius: CGFloat = 13
    static let popoverRadius: CGFloat = 22
    static let pillRadius: CGFloat = 8

    // Typography
    static func bpmFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
    static let statValueFont = Font.system(size: 20, weight: .bold, design: .rounded).monospacedDigit()
    static let cardTitleFont = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let captionFont   = Font.system(size: 11, weight: .regular, design: .rounded)
}

extension View {
    /// Standard translucent card surface with a hairline stroke.
    func cardSurface(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.09))
            )
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Theme.swift
git commit -m "feat(ui): add Theme design-token layer"
```

---

## Task 3: PulsingHeart component

**Files:**
- Create: `HelioBarApp/Views/Components/PulsingHeart.swift`

- [ ] **Step 1: Create `PulsingHeart.swift`**

```swift
import SwiftUI

/// A heart glyph that gently beats at the live BPM. Static when bpm is nil.
struct PulsingHeart: View {
    let bpm: Int?
    var color: Color = Theme.high

    @State private var expanded = false

    /// Half-cycle (beat) duration in seconds, derived from BPM. Clamped so
    /// extreme/garbage values don't produce absurd animation speeds.
    private var beat: Double {
        guard let bpm else { return 0 }
        return 60.0 / Double(min(max(bpm, 40), 200))
    }

    var body: some View {
        Image(systemName: "heart.fill")
            .foregroundStyle(color)
            .scaleEffect(expanded ? 1.0 : 0.82)
            .animation(
                bpm == nil ? nil
                : .easeInOut(duration: beat).repeatForever(autoreverses: true),
                value: expanded
            )
            .onAppear { expanded = bpm != nil }
            .onChange(of: bpm) { _, newValue in
                // Restart the loop so the new BPM's tempo takes effect.
                expanded = false
                if newValue != nil {
                    DispatchQueue.main.async { expanded = true }
                }
            }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    HStack(spacing: 24) {
        PulsingHeart(bpm: 60, color: Theme.resting)
        PulsingHeart(bpm: 120, color: Theme.elevated)
        PulsingHeart(bpm: nil)
    }
    .font(.system(size: 30))
    .padding()
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Components/PulsingHeart.swift
git commit -m "feat(ui): add PulsingHeart component"
```

---

## Task 4: HeartRateRing component (hero)

**Files:**
- Create: `HelioBarApp/Views/Components/HeartRateRing.swift`

- [ ] **Step 1: Create `HeartRateRing.swift`**

```swift
import SwiftUI
import HelioCore

/// Hero heart-rate ring: gradient progress arc with rounded caps + glow,
/// centered BPM, % of max, trend arrow, and a pulsing heart.
struct HeartRateRing: View {
    let bpm: Int?
    let fraction: Double          // 0...1, portion of max HR
    let percentMax: Int?
    let zone: HRZone?
    let trend: HealthStore.Trend?
    let status: SourceStatus

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var ghost: Bool { bpm == nil }
    private var dimmed: Bool { status == .stale }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.07), lineWidth: 14)

            Circle()
                .trim(from: 0, to: ghost ? 0 : clamped)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: Theme.ringGradient),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(clamped, 0.0001))
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(90))            // start from the bottom
                .shadow(color: Theme.color(for: zone).opacity(0.45), radius: 6)
                .animation(.easeInOut(duration: 0.5), value: clamped)

            VStack(spacing: Theme.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(bpm.map(String.init) ?? "—").font(Theme.bpmFont(52))
                    if bpm != nil {
                        Text("bpm")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                if let percentMax {
                    HStack(spacing: 6) {
                        PulsingHeart(bpm: bpm, color: Theme.color(for: zone))
                            .font(.system(size: 13))
                        Text(centerSubtitle(percentMax))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.color(for: zone))
                    }
                }
            }
        }
        .frame(width: 176, height: 176)
        .opacity(dimmed ? 0.5 : (ghost ? 0.6 : 1))
    }

    private func centerSubtitle(_ pct: Int) -> String {
        switch trend {
        case .rising:  return "\(pct)% · ↑"
        case .falling: return "\(pct)% · ↓"
        default:       return "\(pct)%"
        }
    }
}

#if !SWIFT_PACKAGE
#Preview("live") {
    HeartRateRing(bpm: 84, fraction: 0.58, percentMax: 58,
                  zone: .elevated, trend: .rising, status: .live)
        .padding().background(.black)
}
#Preview("idle") {
    HeartRateRing(bpm: nil, fraction: 0, percentMax: nil,
                  zone: nil, trend: nil, status: .idle)
        .padding().background(.black)
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Components/HeartRateRing.swift
git commit -m "feat(ui): add HeartRateRing hero component"
```

---

## Task 5: HRSparkline component

**Files:**
- Create: `HelioBarApp/Views/Components/HRSparkline.swift`

- [ ] **Step 1: Create `HRSparkline.swift`**

```swift
import SwiftUI

/// Compact HR line chart with a soft gradient area fill.
struct HRSparkline: View {
    let values: [Int]
    var color: Color = Theme.elevated

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                let lo = Double(values.min()!)
                let hi = Double(values.max()!)
                let range = max(hi - lo, 1)
                let pts: [CGPoint] = values.enumerated().map { i, v in
                    CGPoint(
                        x: geo.size.width * Double(i) / Double(values.count - 1),
                        y: geo.size.height * (1 - (Double(v) - lo) / range)
                    )
                }

                // Area fill
                Path { p in
                    p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [color.opacity(0.35), color.opacity(0)],
                    startPoint: .top, endPoint: .bottom))

                // Line
                Path { p in
                    p.move(to: pts[0])
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            } else {
                Text("collecting…")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    HRSparkline(values: [62,65,70,68,72,80,95,110,90,75,72,71])
        .frame(height: 46).padding().background(.black)
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Components/HRSparkline.swift
git commit -m "feat(ui): add HRSparkline component"
```

---

## Task 6: StatCard component

**Files:**
- Create: `HelioBarApp/Views/Components/StatCard.swift`

- [ ] **Step 1: Create `StatCard.swift`**

```swift
import SwiftUI

/// One min/avg/max stat in a rounded card.
struct StatCard: View {
    let label: String
    let value: Int?
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Text(value.map(String.init) ?? "—")
                .font(Theme.statValueFont)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardSurface()
    }
}

#if !SWIFT_PACKAGE
#Preview {
    HStack(spacing: 8) {
        StatCard(label: "min", value: 61, tint: Theme.resting)
        StatCard(label: "avg", value: 73)
        StatCard(label: "max", value: 98, tint: Theme.high)
    }
    .padding().background(.black)
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Components/StatCard.swift
git commit -m "feat(ui): add StatCard component"
```

---

## Task 7: ZoneBar component

**Files:**
- Create: `HelioBarApp/Views/Components/ZoneBar.swift`

- [ ] **Step 1: Create `ZoneBar.swift`**

```swift
import SwiftUI
import HelioCore

/// Segmented time-in-zone bar with a legend.
struct ZoneBar: View {
    /// Fractions (0...1) per zone, in display order.
    let fractions: [(zone: HRZone, fraction: Double)]
    let isEmpty: Bool

    private let order: [HRZone] = [.resting, .elevated, .high]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(order, id: \.self) { z in
                        Capsule()
                            .fill(Theme.color(for: z))
                            .frame(width: max(0, geo.size.width * fraction(for: z)))
                    }
                }
            }
            .frame(height: 8)
            .opacity(isEmpty ? 0.15 : 1)

            HStack(spacing: 12) {
                legend("Resting", Theme.resting)
                legend("Elevated", Theme.elevated)
                legend("High", Theme.high)
            }
        }
    }

    private func fraction(for zone: HRZone) -> Double {
        fractions.first { $0.zone == zone }?.fraction ?? 0
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 10, design: .rounded)).foregroundStyle(.tertiary)
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    ZoneBar(fractions: [(.resting, 0.6), (.elevated, 0.3), (.high, 0.1)], isEmpty: false)
        .padding().background(.black)
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Components/ZoneBar.swift
git commit -m "feat(ui): add ZoneBar component"
```

---

## Task 8: BatteryPill component

**Files:**
- Create: `HelioBarApp/Views/Components/BatteryPill.swift`

- [ ] **Step 1: Create `BatteryPill.swift`**

This component owns the battery text formatting (moved out of the old
`MenuContentView`), so the formatting logic lives with the view that renders it.

```swift
import SwiftUI
import HelioCore

/// Strap battery readout: drawn glyph (fill scales with %), percent, time-left.
struct BatteryPill: View {
    let percent: Int?
    let estimate: BatteryEstimate

    var body: some View {
        HStack(spacing: 9) {
            BatteryGlyph(percent: percent, color: color)
            Text(label).font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let right = timeLeft {
                Text(right).font(.system(size: 12, design: .rounded)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .cardSurface()
    }

    private var color: Color {
        guard let percent else { return .secondary }
        return percent < 20 ? Theme.elevated : Theme.resting
    }

    private var label: String {
        guard let percent else { return "Strap —" }
        return "Strap \(percent)%"
    }

    private var timeLeft: String? {
        guard percent != nil else { return nil }
        switch estimate {
        case .calibrating:          return "calibrating"
        case .ready(let remaining): return "~\(Self.formatRemaining(remaining)) left"
        }
    }

    static func formatRemaining(_ remaining: TimeInterval) -> String {
        let hours = Swift.max(0, Int((remaining / 3600).rounded()))
        if hours >= 48 { return "\(Int((Double(hours) / 24).rounded()))d" }
        if hours >= 1  { return "\(hours)h" }
        return "<1h"
    }
}

/// Simple battery icon whose inner fill scales with the percentage.
private struct BatteryGlyph: View {
    let percent: Int?
    let color: Color

    var body: some View {
        let frac = CGFloat(min(max(percent ?? 0, 0), 100)) / 100
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(color, lineWidth: 1.4)
                    .frame(width: 22, height: 13)
                RoundedRectangle(cornerRadius: 1.6)
                    .fill(color)
                    .frame(width: max(0, (22 - 4) * frac), height: 9)
                    .padding(.leading, 2)
            }
            Capsule().fill(color).frame(width: 2, height: 5)
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    VStack(spacing: 8) {
        BatteryPill(percent: 72, estimate: .ready(8 * 3600))
        BatteryPill(percent: 15, estimate: .calibrating)
        BatteryPill(percent: nil, estimate: .calibrating)
    }
    .frame(width: 264).padding().background(.black)
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Components/BatteryPill.swift
git commit -m "feat(ui): add BatteryPill component"
```

---

## Task 9: StatusBadge component

**Files:**
- Create: `HelioBarApp/Views/Components/StatusBadge.swift`

- [ ] **Step 1: Create `StatusBadge.swift`**

```swift
import SwiftUI
import HelioCore

/// The live/reconnecting/idle/error indicator under the ring.
struct StatusBadge: View {
    let status: SourceStatus

    var body: some View {
        switch status {
        case .live:
            label("live", Theme.resting, dot: true)
        case .stale:
            label("reconnecting", .secondary, dot: true)
        case .idle:
            Text("Enable Heart Rate Push in Zepp")
                .font(Theme.captionFont).foregroundStyle(.secondary)
        case .error(let message):
            Text(message)
                .font(Theme.captionFont).foregroundStyle(Theme.elevated)
                .multilineTextAlignment(.center)
        }
    }

    private func label(_ text: String, _ color: Color, dot: Bool) -> some View {
        HStack(spacing: 6) {
            if dot {
                Circle().fill(color).frame(width: 7, height: 7)
                    .shadow(color: color, radius: 3)
            }
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    VStack(spacing: 12) {
        StatusBadge(status: .live)
        StatusBadge(status: .stale)
        StatusBadge(status: .idle)
        StatusBadge(status: .error("Bluetooth off"))
    }
    .padding().background(.black)
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Components/StatusBadge.swift
git commit -m "feat(ui): add StatusBadge component"
```

---

## Task 10: IconButton component

**Files:**
- Create: `HelioBarApp/Views/Components/IconButton.swift`

- [ ] **Step 1: Create `IconButton.swift`**

```swift
import SwiftUI

/// Square card button holding a single SF Symbol — used in the popover toolbar.
struct IconButton: View {
    let systemName: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .cardSurface()
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

#if !SWIFT_PACKAGE
#Preview {
    HStack(spacing: 8) {
        IconButton(systemName: "wind", help: "Breathe", tint: .blue) {}
        IconButton(systemName: "arrow.counterclockwise", help: "Reset") {}
        IconButton(systemName: "gearshape", help: "Settings") {}
        IconButton(systemName: "power", help: "Quit") {}
    }
    .frame(width: 264).padding().background(.black)
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Components/IconButton.swift
git commit -m "feat(ui): add IconButton component"
```

---

## Task 11: Recompose MenuContentView (Option A)

**Files:**
- Modify (full rewrite): `HelioBarApp/Views/MenuContentView.swift`

- [ ] **Step 1: Replace `MenuContentView.swift` with the composed layout**

The public signature is unchanged: `MenuContentView(store: HealthStore, onSettings: () -> Void)`. The breathing toggle keeps the existing `@State` swap.

```swift
import SwiftUI
import HelioCore

struct MenuContentView: View {
    let store: HealthStore
    var onSettings: () -> Void
    @State private var breathing = false

    var body: some View {
        Group {
            if breathing {
                BreathingView(store: store) { breathing = false }
            } else {
                main
            }
        }
        .padding(Theme.lg)
        .frame(width: 300)
        .background(.black.opacity(0.001))   // ensures the hosting view fills the popover
    }

    private var main: some View {
        VStack(spacing: Theme.md) {
            HeartRateRing(
                bpm: store.liveHR,
                fraction: Double(store.percentMax ?? 0) / 100,
                percentMax: store.percentMax,
                zone: store.hrZone,
                trend: store.hrTrend,
                status: store.hrStatus
            )
            StatusBadge(status: store.hrStatus)

            card(title: "Last 2 min") {
                HRSparkline(values: store.recent).frame(height: 46)
            }

            HStack(spacing: Theme.sm) {
                StatCard(label: "min", value: store.sessionMin, tint: Theme.resting)
                StatCard(label: "avg", value: store.sessionAvg)
                StatCard(label: "max", value: store.sessionMax, tint: Theme.high)
            }

            card(title: "Time in zone") {
                ZoneBar(
                    fractions: [
                        (.resting,  store.zoneFraction(.resting)),
                        (.elevated, store.zoneFraction(.elevated)),
                        (.high,     store.zoneFraction(.high)),
                    ],
                    isEmpty: store.zoneCounts.isEmpty
                )
            }

            BatteryPill(percent: store.batteryPercent, estimate: store.batteryEstimate)

            HStack(spacing: Theme.sm) {
                IconButton(systemName: "wind", help: "Breathe", tint: .blue) { breathing = true }
                IconButton(systemName: "arrow.counterclockwise", help: "Reset session") { store.resetSession() }
                IconButton(systemName: "gearshape", help: "Settings", action: onSettings)
                IconButton(systemName: "power", help: "Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(Theme.cardTitleFont).foregroundStyle(.tertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .cardSurface()
    }
}

#if !SWIFT_PACKAGE
#Preview("live") {
    let s = HealthStore()
    [62,65,70,68,72,80,95,110,90,75,72,71].forEach { s.updateHR($0) }
    return MenuContentView(store: s, onSettings: {}).background(.black)
}

#Preview("idle") {
    MenuContentView(store: HealthStore(), onSettings: {}).background(.black)
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/MenuContentView.swift
git commit -m "feat(ui): recompose popover with Fitness-style components"
```

---

## Task 12: Restyle BreathingView

**Files:**
- Modify (full rewrite): `HelioBarApp/Views/BreathingView.swift`

- [ ] **Step 1: Replace `BreathingView.swift`**

Behavior is preserved (4s inhale/exhale, live HR, start/low/↓ delta, Done). Only visuals change: a gradient orb in the ring's color language.

```swift
import SwiftUI
import HelioCore

/// Guided breathing with live HR biofeedback — shown inline in the dropdown.
struct BreathingView: View {
    let store: HealthStore
    var onClose: () -> Void

    @State private var inhaling = false
    @State private var startHR: Int?
    @State private var lowHR: Int?
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Theme.md) {
            HStack {
                Text("Breathe").font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button("Done", action: onClose).controlSize(.small)
            }

            Text(inhaling ? "Inhale…" : "Exhale…")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Theme.resting.opacity(0.35), Color.blue.opacity(0.12)],
                        center: .center, startRadius: 4, endRadius: 90))
                Circle().strokeBorder(Theme.resting.opacity(0.7), lineWidth: 2)
            }
            .frame(width: inhaling ? 150 : 80, height: inhaling ? 150 : 80)
            .shadow(color: Theme.resting.opacity(0.4), radius: 12)
            .animation(.easeInOut(duration: 4), value: inhaling)
            .frame(height: 160)   // reserve space so the popover doesn't jump

            VStack(spacing: 2) {
                Text(store.liveHR.map { "\($0) bpm" } ?? "—")
                    .font(Theme.bpmFont(26))
                if let s = startHR, let l = lowHR {
                    Text("start \(s) · low \(l) · ↓\(Swift.max(0, s - l))")
                        .font(Theme.captionFont).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { startHR = store.liveHR; lowHR = store.liveHR; inhaling = true }
        .onReceive(timer) { _ in inhaling.toggle() }
        .onChange(of: store.liveHR) { _, hr in
            guard let hr else { return }
            if startHR == nil { startHR = hr }
            lowHR = Swift.min(lowHR ?? hr, hr)
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    let s = HealthStore(); s.updateHR(72)
    return BreathingView(store: s) {}.frame(width: 300).padding().background(.black)
}
#endif
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/BreathingView.swift
git commit -m "feat(ui): restyle BreathingView with gradient orb"
```

---

## Task 13: Restyle SettingsView

**Files:**
- Modify: `HelioBarApp/Views/SettingsView.swift`

- [ ] **Step 1: Add section icons + app header to the Form**

Keep every `@AppStorage` binding and the `setLaunch` logic exactly as-is. Only add `Label`s with SF Symbols to section headers and a small header row. Replace the `body` with:

```swift
    var body: some View {
        Form {
            Section {
                Stepper("Age: \(age)", value: $age, in: 10...100)
                Text("Max HR ≈ \(220 - age) bpm · zones scale to this")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Label("You", systemImage: "person.fill")
            }
            Section {
                Toggle("Notify when HR stays high", isOn: $alertEnabled)
                Stepper("Above \(alertThreshold) bpm", value: $alertThreshold, in: 80...200, step: 5)
                Stepper("For \(alertDurationMin) min", value: $alertDurationMin, in: 1...30)
            } header: {
                Label("Elevated-HR alert", systemImage: "heart.text.square.fill")
            }
            Section {
                Toggle("Notify when strap battery is low", isOn: $batteryAlertEnabled)
                Stepper("At or below \(batteryAlertThreshold)%", value: $batteryAlertThreshold, in: 5...50, step: 5)
            } header: {
                Label("Strap battery alert", systemImage: "battery.25percent")
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
                if let launchAtLoginError {
                    Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Label("System", systemImage: "power")
            }
        }
        .formStyle(.grouped)
        .frame(width: 330, height: 400)
    }
```

(Leave the property declarations and `setLaunch(_:)` method unchanged. Note the height changed 380 → 400 to fit the section headers; also update the `NSWindow` content rect in Task 14 note below if needed — it is cosmetic and the form scrolls regardless.)

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/SettingsView.swift
git commit -m "feat(ui): restyle Settings with section iconography"
```

---

## Task 14: Menu-bar item as a custom NSImage

**Files:**
- Create: `HelioBarApp/MenuBarIcon.swift`
- Modify: `Package.swift` (add the new source file)
- Modify: `HelioBarApp/HelioBarApp.swift:50-75` (`updateTitle` → image), `:32-36` (button setup)

- [ ] **Step 1: Create `MenuBarIcon.swift`**

Draws the dark pill with a zone-colored heart + centered, fixed-width number.

```swift
import AppKit
import HelioCore

/// Renders the menu-bar item as a fixed-width dark pill with a zone-colored
/// heart + BPM. Drawn as a non-template NSImage so the color is preserved.
enum MenuBarIcon {
    private static let size = NSSize(width: 58, height: 20)

    static func image(bpm: Int?, zone: HRZone?, status: SourceStatus) -> NSImage {
        let contentColor: NSColor
        switch status {
        case .stale:                 contentColor = .secondaryLabelColor
        case .idle, .error:          contentColor = .tertiaryLabelColor
        case .live:
            switch zone {
            case .elevated: contentColor = .systemOrange
            case .high:     contentColor = .systemRed
            default:        contentColor = .systemGreen
            }
        }

        let image = NSImage(size: size, flipped: false) { rect in
            // Dark pill
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.55).setFill()
            pill.fill()
            NSColor.white.withAlphaComponent(0.08).setStroke()
            pill.lineWidth = 1
            pill.stroke()

            // Heart glyph
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            if let heart = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig) {
                let tinted = heart
                tinted.isTemplate = true
                let hRect = NSRect(x: 7, y: (rect.height - 11) / 2, width: 12, height: 11)
                contentColor.set()
                tinted.draw(in: hRect)
            }

            // Number (centered in a fixed slot for up to 3 digits)
            let text = bpm.map(String.init) ?? "–"
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: contentColor,
                .paragraphStyle: para,
            ]
            let numberSlot = NSRect(x: 22, y: (rect.height - 14) / 2 - 1, width: 30, height: 16)
            (text as NSString).draw(in: numberSlot, withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        return image
    }
}
```

- [ ] **Step 2: Add the file to SwiftPM sources**

In `Package.swift`, in the `HelioBar` executable target's `sources:` array, add `"MenuBarIcon.swift"` after `"HeartRateMonitor.swift"`:

```swift
            sources: [
                "HelioBarApp.swift",
                "AppModel.swift",
                "HeartRateMonitor.swift",
                "MenuBarIcon.swift",
                "Views",
            ]
```

- [ ] **Step 3: Wire it into AppDelegate**

In `HelioBarApp/HelioBarApp.swift`, in `applicationDidFinishLaunching`, replace the button title setup:

```swift
        if let button = statusItem.button {
            button.title = "♥ –"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
```
with:
```swift
        if let button = statusItem.button {
            button.image = MenuBarIcon.image(bpm: nil, zone: nil, status: .idle)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
```

Then replace the entire `updateTitle()` method with:

```swift
    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let store = model.store
        button.image = MenuBarIcon.image(bpm: store.liveHR,
                                         zone: store.hrZone,
                                         status: store.hrStatus)
    }
```

- [ ] **Step 4: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add HelioBarApp/MenuBarIcon.swift Package.swift HelioBarApp/HelioBarApp.swift
git commit -m "feat(ui): draw menu-bar item as fixed-width zone-colored pill"
```

---

## Task 15: Docs + full verification

**Files:**
- Modify: `README.md` (macOS requirement)
- Modify: `docs/CONTEXT.md` (note the bump)

- [ ] **Step 1: Update the macOS requirement in README**

Find the line in `README.md` stating the macOS requirement (search for `macOS 14`) and change it to `macOS 26`. If no such line exists, add under the requirements/install section: `Requires macOS 26 or later.`

Run: `grep -n "macOS 1" README.md` first to locate; edit each hit to `macOS 26` where it refers to the minimum.

- [ ] **Step 2: Note the bump in CONTEXT.md**

In `docs/CONTEXT.md` §1, change `deployment target **macOS 14**` to `deployment target **macOS 26** (raised from 14 for the UI redesign)`.

- [ ] **Step 3: Run the logic tests (prove HelioCore untouched)**

Run: `cd HelioCore && swift test 2>&1 | tail -15`
Expected: all tests pass (no failures).

- [ ] **Step 4: Full release build**

Run: `swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 5: Manual verification (launch the app)**

Run: `./scripts/install-and-run.sh` (or build + run via Xcode).
Confirm:
- Menu-bar pill shows a dark capsule with a colored heart + number; width does not shift when the value changes digits.
- Clicking opens the redesigned popover (ring hero, sparkline, stats, zone bar, battery, toolbar).
- Idle state (before data) shows the ghosted ring + "Enable Heart Rate Push".
- Breathe button shows the gradient-orb breathing view; Done returns.
- Settings opens with section icons and functions (age, alerts, launch-at-login).

- [ ] **Step 6: Commit**

```bash
git add README.md docs/CONTEXT.md
git commit -m "docs: note macOS 26 requirement after UI redesign"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- §3 Theme → Task 2 ✓ · §3.2 components → Tasks 3–10 ✓ · §4 popover → Task 11 ✓ ·
  §5 menu-bar → Task 14 ✓ · §6 breathing → Task 12 ✓ · §7 settings → Task 13 ✓ ·
  §8 file changes → all tasks ✓ (incl. Package.swift in Task 14, project.yml/Info.plist in Task 1) ·
  §2 macOS 26 bump → Task 1 ✓ · §10 testing → Task 15 ✓ · §11 README note → Task 15 ✓.
- §9 performance: addressed in `PulsingHeart`/`HeartRateRing` (animation only on value change). No dedicated task needed.

**Type consistency:** `HeartRateRing` consumes `HealthStore.Trend`, `HRZone?`, `SourceStatus`, `BatteryEstimate` exactly as defined in `HelioCore`. `BatteryPill` uses `BatteryEstimate.calibrating`/`.ready(TimeInterval)` (matches `BatteryEstimateEngine.swift`). `MenuContentView` calls `store.percentMax`, `store.hrZone`, `store.hrTrend`, `store.zoneFraction(_:)`, `store.zoneCounts`, `store.sessionMin/Avg/Max`, `store.recent`, `store.batteryPercent`, `store.batteryEstimate` — all verified against `HealthStore.swift`. `MenuBarIcon.image(bpm:zone:status:)` signature matches the AppDelegate call site.

**Placeholder scan:** none — every code step contains complete code.
