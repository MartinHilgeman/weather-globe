#!/bin/bash
# Persists the chosen xplanet projection for the weather-globe render script.
# Usage: set-projection.sh <projection-value>   (empty string = classic default)
set -euo pipefail

VALID=(ancient azimuthal bonne equal_area gnomonic hemisphere lambert mercator mollweide orthographic peters polyconic rectangular tsc)
VALUE="${1:-}"

if [[ -n $VALUE ]]; then
  ok=0
  for v in "${VALID[@]}"; do
    [[ $v == "$VALUE" ]] && ok=1 && break
  done
  if [[ $ok -eq 0 ]]; then
    echo "set-projection.sh: unknown projection '$VALUE'" >&2
    exit 1
  fi
fi

STATE_DIR="$HOME/.local/state/omarchy/weather-globe"
mkdir -p "$STATE_DIR"
printf '%s' "$VALUE" > "$STATE_DIR/projection"
