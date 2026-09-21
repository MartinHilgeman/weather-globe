#!/bin/bash
# Persists the "show temperature" toggle for the weather-globe render script.
# Only has an effect when zoom-location is also on. Usage: set-temperature.sh <0|1>
set -euo pipefail

VALUE="${1:-0}"
[[ $VALUE == "0" || $VALUE == "1" ]] || { echo "set-temperature.sh: expected 0 or 1, got '$VALUE'" >&2; exit 1; }

STATE_DIR="$HOME/.local/state/omarchy/weather-globe"
mkdir -p "$STATE_DIR"
if [[ $VALUE == "1" ]]; then
  printf '1' > "$STATE_DIR/show-temperature"
else
  rm -f "$STATE_DIR/show-temperature"
fi
