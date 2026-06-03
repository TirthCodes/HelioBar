#!/bin/zsh

set -euo pipefail

app_path="$HOME/Applications/HelioBar.app"

if pgrep -f 'HelioBar.app/Contents/MacOS/HelioBar' >/dev/null 2>&1; then
  echo "Stopping running HelioBar instance..."
  pkill -f 'HelioBar.app/Contents/MacOS/HelioBar'
fi

if [[ -d "$app_path" ]]; then
  echo "Removing $app_path..."
  rm -rf "$app_path"
else
  echo "No installed app found at $app_path"
fi
