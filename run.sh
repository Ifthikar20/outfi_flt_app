#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# Outfi — build, install & run script (iOS)
# ═══════════════════════════════════════════════════════════════
#
# Usage:
#   ./run.sh                  # debug run (hot reload)
#   ./run.sh --install        # full clean + release install to iPhone
#   ./run.sh --install --fast # skip clean, release install to iPhone
#   ./run.sh --device ID      # target a specific device

set -euo pipefail

cd "$(dirname "$0")"

# ── Colors ──────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# ── Helpers ─────────────────────────────────────────
timestamp() { date '+%H:%M:%S'; }
log()   { echo -e "${DIM}$(timestamp)${NC} ${GREEN}▸${NC} $*"; }
warn()  { echo -e "${DIM}$(timestamp)${NC} ${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${DIM}$(timestamp)${NC} ${RED}✗${NC} $*"; }
step()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }
ok()    { echo -e "${DIM}$(timestamp)${NC} ${GREEN}✓${NC} $*"; }

timer_start() { STEP_START=$(date +%s); }
timer_end()   {
  local elapsed=$(( $(date +%s) - STEP_START ))
  echo -e "${DIM}$(timestamp)${NC} ${DIM}↳ completed in ${elapsed}s${NC}"
}

# ── Parse args ──────────────────────────────────────
FAST=0
INSTALL=0
DEVICE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast)    FAST=1; shift ;;
    --install) INSTALL=1; shift ;;
    --device)  DEVICE="$2"; shift 2 ;;
    *) err "Unknown arg: $1"; exit 1 ;;
  esac
done

# ── Header ──────────────────────────────────────────
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         ${CYAN}Outfi iOS Build Tool${NC}${BOLD}          ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════╝${NC}"
echo ""

MODE="debug"
[[ $INSTALL -eq 1 ]] && MODE="release"
log "Mode: ${BOLD}${MODE}${NC} | Fast: ${FAST} | Device: ${DEVICE:-auto}"

# ── Step 1: Flutter version ─────────────────────────
step "1/7 Flutter Environment"
timer_start
flutter --version 2>&1 | head -5
timer_end

# ── Step 2: Clean (unless --fast) ───────────────────
if [[ $FAST -eq 0 ]]; then
  step "2/7 Cleaning Build Artifacts"
  timer_start
  log "flutter clean..."
  flutter clean 2>&1 | tail -5
  log "Removing ios/Pods, Podfile.lock, .symlinks..."
  rm -rf ios/Pods ios/Podfile.lock ios/.symlinks ios/Flutter/Flutter.framework ios/Flutter/Flutter.podspec 2>/dev/null || true
  ok "Clean complete"
  timer_end
else
  step "2/7 Clean (skipped — fast mode)"
  log "Using cached build artifacts"
fi

# ── Step 3: Pub get ─────────────────────────────────
step "3/7 Fetching Dart Packages"
timer_start
log "flutter pub get..."
flutter pub get 2>&1 | grep -E "^(Got|Changed|Downloading|Resolving)" || true
ok "Packages resolved"
timer_end

# ── Step 4: CocoaPods ───────────────────────────────
step "4/7 Installing CocoaPods"
timer_start
log "pod install --repo-update..."
( cd ios && pod install --repo-update 2>&1 | grep -E "^(Installing|Generating|Integrating|Pod installation|Analyzing)" ) || true
ok "Pods installed"
timer_end

# ── Step 5: Doctor ──────────────────────────────────
step "5/7 Flutter Doctor"
timer_start
flutter doctor -v 2>&1 | grep -E "^\[|•" | head -15
timer_end

# ── Step 6: Detect device ──────────────────────────
step "6/7 Device Detection"
timer_start

# List all devices
log "Scanning for connected devices..."
flutter devices 2>&1 | grep -E "•|Found" || true

if [[ $INSTALL -eq 1 ]] && [[ -z "$DEVICE" ]]; then
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

if [[ -n "$DEVICE" ]]; then
  ok "Target device: ${BOLD}${DEVICE}${NC}"
else
  warn "No specific device targeted — Flutter will pick one"
fi
timer_end

# ── Step 7: Build & Install/Run ─────────────────────
if [[ $INSTALL -eq 1 ]]; then
  step "7/7 Release Build + Install"

  # Auto-bump version
  if [[ -x "./scripts/bump-version.sh" ]]; then
    log "Auto-bumping build number..."
    ./scripts/bump-version.sh build
    flutter pub get > /dev/null 2>&1
  fi

  VERSION=$(awk '/^version:/ {print $2}' pubspec.yaml)
  log "Building version ${BOLD}${VERSION}${NC}"

  # Build
  timer_start
  log "flutter build ios --release (this takes 30-90s)..."
  flutter build ios --release 2>&1 | while IFS= read -r line; do
    case "$line" in
      *"Running Xcode"*) log "$line" ;;
      *"Xcode build done"*) ok "$line" ;;
      *"Built build"*) ok "$line" ;;
      *"Error"*|*"error"*) err "$line" ;;
      *"Warning"*|*"warning"*) warn "$line" ;;
    esac
  done
  timer_end

  # Install via devicectl (more reliable than flutter run for wireless)
  if [[ -n "$DEVICE" ]]; then
    step "Installing to device via devicectl"
    timer_start
    log "xcrun devicectl device install app..."
    xcrun devicectl device install app \
      --device "$DEVICE" \
      build/ios/iphoneos/Runner.app 2>&1 | while IFS= read -r line; do
        case "$line" in
          *"Complete"*) ok "Install complete!" ;;
          *"bundleID"*) log "$line" ;;
          *"%"*)
            # Extract percentage for progress bar
            pct=$(echo "$line" | grep -oE '[0-9]+%' | tail -1)
            if [[ -n "$pct" ]]; then
              echo -ne "\r${DIM}$(timestamp)${NC} ${BLUE}▸${NC} Installing: ${BOLD}${pct}${NC}  "
            fi
            ;;
          *"Error"*|*"error"*) err "$line" ;;
          *) [[ -n "$line" ]] && log "$line" ;;
        esac
      done
    echo "" # newline after progress
    timer_end
  else
    warn "No device ID — falling back to flutter run --release"
    flutter run --release
  fi

  # Done
  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════${NC}"
  echo -e "${GREEN}  ✅ Outfi ${VERSION} installed on iPhone${NC}"
  echo -e "${GREEN}  Unlock your phone and tap the Outfi icon${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════${NC}"
  echo ""

else
  step "7/7 Debug Run (hot reload)"
  log "Starting debug build on device..."
  warn "This is a DEBUG build — app won't run standalone after quit"
  warn "Use './run.sh --install' for standalone release install"
  echo ""
  if [[ -n "$DEVICE" ]]; then
    flutter run -d "$DEVICE"
  else
    flutter run
  fi
fi
