#!/usr/bin/env bash
# Outfi — full install & run script (iOS)
# Usage:
#   ./run.sh                  # debug run (hot reload; app won't work after you quit)
#   ./run.sh --install        # release build + install standalone (runs from home screen, no terminal needed)
#   ./run.sh --fast           # skip clean, just pub get + pod install + run
#   ./run.sh --device ID      # run on a specific device (flutter devices to list)

set -e

cd "$(dirname "$0")"

FAST=0
INSTALL=0
DEVICE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast)    FAST=1; shift ;;
    --install) INSTALL=1; shift ;;
    --device)  DEVICE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "==> Flutter version"
flutter --version

if [[ $FAST -eq 0 ]]; then
  echo "==> Cleaning build artifacts"
  flutter clean
  rm -rf ios/Pods ios/Podfile.lock ios/.symlinks ios/Flutter/Flutter.framework ios/Flutter/Flutter.podspec
fi

echo "==> Fetching Dart/Flutter packages"
flutter pub get

echo "==> Installing CocoaPods (iOS)"
( cd ios && pod install --repo-update )

echo "==> Running flutter doctor (quick check)"
flutter doctor -v | head -40 || true

echo "==> Booting iOS simulator if none running"
if ! xcrun simctl list devices booted | grep -q Booted; then
  open -a Simulator
  # Give it a moment to come up
  sleep 3
fi

if [[ $INSTALL -eq 1 ]]; then
  # Release builds only work on a real iPhone — iOS simulator does not
  # support AOT-compiled Flutter release binaries.
  echo "==> Building & installing RELEASE build to physical iOS device"
  echo "   (Release mode requires a real iPhone, not a simulator.)"

  # Auto-bump the build number on every deployment so Apple accepts it and
  # the in-app version label always reflects a fresh install.
  if [[ -x "./scripts/bump-version.sh" ]]; then
    echo "==> Auto-bumping build number"
    ./scripts/bump-version.sh build
    # pubspec.yaml changed — refresh generated version metadata
    flutter pub get > /dev/null
  fi

  if [[ -z "$DEVICE" ]]; then
    # Auto-pick the first connected physical iOS device by parsing JSON with python3.
    DEVICE="$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
try:
    devs = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for d in devs:
    if d.get("targetPlatform", "").startswith("ios") \
       and not d.get("emulator", False) \
       and "simulator" not in (d.get("sdk", "") or "").lower():
        print(d.get("id", ""))
        break
' 2>/dev/null)"
  fi

  if [[ -z "$DEVICE" ]]; then
    echo ""
    echo "⚠️  Could not auto-detect a physical iOS device via JSON."
    echo "   Falling back to 'flutter run --release' with no -d flag."
    echo "   (This works when exactly one device is connected.)"
    flutter run --release
  else
    echo "   Target device: $DEVICE"
    flutter run --release -d "$DEVICE"
  fi

  echo ""
  echo "✅ App installed on your iPhone. You can close this terminal."
  echo "   Tap the Outfi icon on your phone's home screen to relaunch."
else
  echo "==> Launching app (debug, hot-reload)"
  echo "   ⚠️  This is a DEBUG build — when you press 'q', the app will not run standalone."
  echo "       Use './run.sh --install' for a standalone release install on a real iPhone."
  if [[ -n "$DEVICE" ]]; then
    flutter run -d "$DEVICE"
  else
    flutter run
  fi
fi
