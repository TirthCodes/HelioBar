# HelioBar

A native macOS **menu bar app** that shows your **live heart rate** from an
[Amazfit Helio Strap](https://us.amazfit.com/products/helio-strap) — read directly
over Bluetooth, no cloud, no account, nothing leaves your Mac.

The strap broadcasts heart rate over the standard BLE Heart Rate service, and
HelioBar reads it straight from CoreBluetooth.

## 📥 Just want to use it? (no GitHub or coding needed)

1. **[Download HelioBar here](https://github.com/TirthCodes/HelioBar/releases/latest)** — grab `HelioBar.zip` under *Assets*.
2. **Double-click the zip** to unzip → you get `HelioBar.app`.
3. **Drag `HelioBar.app` into your Applications folder.**
4. **First time only:** macOS says *"Apple cannot verify this app"* (it's a free app, not paid-signed with Apple). To open it: **right-click** the app → **Open** → **Open** again — or go to **System Settings → Privacy & Security** and click **"Open Anyway"**.
5. Click **Allow** for Bluetooth.

Then in the **Zepp** app: Device → Helio Strap → **Health Monitoring** → turn on **Heart Rate Push**. Your live heart rate shows up in the menu bar within seconds.

> 💡 **Notch tip:** if the icon hides under the notch, hold **⌘** and drag it out to the right.

The rest of this README is for developers who want to build it themselves.

## Features

- **Live HR in the menu bar** — the number, zone-tinted (green / orange / red) with a trend arrow (`♥ 84 ↑`)
- **Dropdown** with a live HR **sparkline**, session **min / avg / max**, a **time-in-zone** bar, and **% of max HR**
- **Strap battery** — reads battery percentage directly from the standard BLE Battery service
- **Personalized zones** — set your age; zones scale to your estimated max HR (≈ 220 − age)
- **Elevated-HR alerts** — a macOS notification when your HR stays above a threshold for N minutes (a desk-stress nudge)
- **Breathing biofeedback** — a guided inhale/exhale timer, inline in the dropdown, so you can watch your HR settle in real time
- **Launch at login**, no Dock icon, App Sandbox on

## Requirements

- macOS 14+
- Apple Command Line Tools (`xcode-select -p` should point at Command Line Tools) or full Xcode
- An Amazfit Helio Strap (or any device that broadcasts the standard BLE Heart Rate service `0x180D`)

## Setup

1. In the **Zepp** app: Device → Helio Strap → Health Monitoring → enable **Heart Rate Push**.
   This makes the strap broadcast HR over standard BLE.
2. Launch HelioBar and **allow Bluetooth** when prompted.
3. The menu bar number goes live within a few seconds.

> **Notch tip:** on a crowded notch-MacBook menu bar, the icon can land *under* the
> notch. Hold **⌘** and drag it out to the right — macOS remembers the spot.

## Build & install

### Command Line Tools path

You do not need full Xcode to run HelioBar. If Apple Command Line Tools are installed,
you can build, install, and launch it with one script:

```bash
git clone https://github.com/TirthCodes/HelioBar.git
cd HelioBar
./scripts/install-and-run.sh
```

This installs a signed app bundle at `~/Applications/HelioBar.app` and launches it.
That stable install location is what macOS uses for permissions, notifications,
and **Launch at login** registration.

To remove it:

```bash
./scripts/uninstall.sh
```

Then in HelioBar, open `Settings` and turn on `Launch at login`. You can verify
that macOS registered it in `System Settings` → `General` → `Login Items & Extensions`.

### Full Xcode path

```bash
brew install xcodegen          # one-time
git clone https://github.com/TirthCodes/HelioBar.git
cd HelioBar
xcodegen generate
xcodebuild -scheme HelioBar -configuration Release -derivedDataPath build build
cp -R build/Build/Products/Release/HelioBar.app /Applications/
open /Applications/HelioBar.app
```

Run the logic package build with `cd HelioCore && swift build`.

If full Xcode is installed, you can also run the logic tests with `cd HelioCore && swift test`.

## Architecture

- **`HelioCore/`** — a Swift package with the pure, unit-tested logic: `HealthStore`
  (the single source of truth), the BLE Heart Rate packet parser, HR-zone math, and the
  elevated-HR alert engine. Run via `swift test`.
- **`HelioBarApp/`** — the macOS app sources: an AppKit `NSStatusItem` + `NSPopover`
  driving SwiftUI views, and a CoreBluetooth `HeartRateMonitor`. The menu bar uses
  AppKit (not SwiftUI's `MenuBarExtra`) because `NSStatusItem` survives sleep/wake reliably.
- **Root `Package.swift`** — a SwiftPM executable wrapper so the app can be built with
  Apple Command Line Tools, without relying on Xcode's build system.

The UI only ever reads `HealthStore`; the BLE monitor pushes into it. Each piece has one job
and is testable in isolation.

## Notes

- HRV isn't supported: the strap's BLE broadcast sends only the averaged BPM, not the
  beat-to-beat (RR) intervals HRV requires.
- Stress / energy / readiness need the Zepp cloud, which this app intentionally avoids.
  Earlier commits explored a (working) cloud integration; it was removed to keep HelioBar
  fully local. It's in the git history if you want it.

## License

MIT
