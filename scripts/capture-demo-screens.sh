#!/bin/bash
set -euo pipefail

usage() { echo "usage: $0 SIM_UDID APP_PATH PHOTOS_DIR OUT_DIR ROUTE..." >&2; exit 64; }
[ $# -ge 5 ] || usage

SIM=$1; APP=$2; PHOTOS=$3; OUT=$4; shift 4
BUNDLE=com.guitaripod.livingdex
SIMCTL=/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl
SETTLE=${SETTLE:-16}

mkdir -p "$OUT"
"$SIMCTL" status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null
"$SIMCTL" location "$SIM" set 60.1699,24.9384

for route in "$@"; do
  "$SIMCTL" terminate "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
  "$SIMCTL" uninstall "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
  "$SIMCTL" install "$SIM" "$APP"
  "$SIMCTL" privacy "$SIM" grant location "$BUNDLE"
  "$SIMCTL" privacy "$SIM" grant camera "$BUNDLE"
  SIMCTL_CHILD_LIVINGDEX_DEMO="$route" SIMCTL_CHILD_LIVINGDEX_DEMO_PHOTOS="$PHOTOS" \
    "$SIMCTL" launch "$SIM" "$BUNDLE" >/dev/null
  sleep "$SETTLE"
  "$SIMCTL" io "$SIM" screenshot "$OUT/$route.png" >/dev/null
  echo "captured $route"
done
