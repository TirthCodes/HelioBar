#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
binary_path="$repo_root/.build/release/HelioBLEInspector"
app_path="$repo_root/.build/HelioBLEInspector.app"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
plist_path="$contents_path/Info.plist"

echo "Building HelioBLEInspector..."
swift build --package-path "$repo_root" -c release --product HelioBLEInspector

echo "Assembling signed inspector app..."
mkdir -p "$macos_path"
cp "$binary_path" "$macos_path/HelioBLEInspector"

cat > "$plist_path" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>HelioBLEInspector</string>
  <key>CFBundleIdentifier</key><string>com.helio.HelioBLEInspector</string>
  <key>CFBundleName</key><string>HelioBLEInspector</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>HelioBLEInspector scans the strap to list Bluetooth services and characteristics.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app_path"

echo "Running HelioBLEInspector. Press Ctrl-C to stop after collecting data."
"$macos_path/HelioBLEInspector"
