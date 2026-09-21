#!/bin/bash
# Persists the "zoom to current location" toggle for the weather-globe render
# script. Usage: set-zoom.sh <0|1>
set -euo pipefail

VALUE="${1:-0}"
[[ $VALUE == "0" || $VALUE == "1" ]] || { echo "set-zoom.sh: expected 0 or 1, got '$VALUE'" >&2; exit 1; }

STATE_DIR="$HOME/.local/state/omarchy/weather-globe"
mkdir -p "$STATE_DIR"
if [[ $VALUE == "1" ]]; then
  printf '1' > "$STATE_DIR/zoom-location"
else
  rm -f "$STATE_DIR/zoom-location"
fi
