#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
build_dir="$repo_root/.build"
binary_path="$build_dir/release/HelioBar"
app_path="$HOME/Applications/HelioBar.app"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
plist_path="$contents_path/Info.plist"
source_plist="$repo_root/HelioBarApp/Resources/Info.plist"
entitlements_path="$repo_root/HelioBarApp/Resources/HelioBar.entitlements"

echo "Building HelioBar with SwiftPM..."
swift build --package-path "$repo_root" -c release

echo "Installing app bundle to $app_path..."
mkdir -p "$macos_path"
cp "$binary_path" "$macos_path/HelioBar"
cp "$source_plist" "$plist_path"
plutil -replace CFBundleExecutable -string HelioBar "$plist_path"
plutil -replace CFBundlePackageType -string APPL "$plist_path"

echo "Codesigning app bundle (with sandbox + Bluetooth entitlements)..."
codesign --force --sign - --entitlements "$entitlements_path" "$app_path"

if pgrep -f 'HelioBar.app/Contents/MacOS/HelioBar' >/dev/null 2>&1; then
  echo "Stopping running HelioBar instance..."
  pkill -f 'HelioBar.app/Contents/MacOS/HelioBar'
fi

echo "Launching HelioBar..."
open "$app_path"
