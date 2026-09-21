#!/bin/bash
# Installs the Weather Globe plugin: an xplanet desktop background driven by
# live NASA satellite cloud/storm imagery, plus a bar widget for status and
# manual refresh. Safe to re-run.
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="${USER:-$(id -un)}.weather-globe"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
SYSTEMD_DIR="$HOME/.config/systemd/user"
STATE_DIR="$HOME/.local/state/omarchy/weather-globe"

echo "Installing Weather Globe plugin from $PKG_DIR"

omarchy pkg add xplanet imagemagick unzip

mkdir -p "$STATE_DIR" "$SYSTEMD_DIR" "$PLUGINS_DIR"

CITIES_DB="$STATE_DIR/cities15000.txt"
if [[ ! -f "$CITIES_DB" ]]; then
  echo "Downloading city dataset for temperature markers (GeoNames cities15000)..."
  CITIES_TMPDIR="$(mktemp -d)"
  if curl -fsSL --max-time 60 -o "$CITIES_TMPDIR/cities15000.zip" \
      "http://download.geonames.org/export/dump/cities15000.zip" \
    && unzip -p "$CITIES_TMPDIR/cities15000.zip" cities15000.txt > "$CITIES_TMPDIR/cities15000.txt"; then
    mv "$CITIES_TMPDIR/cities15000.txt" "$CITIES_DB"
    echo "City dataset installed ($(wc -l < "$CITIES_DB") cities)."
  else
    echo "WARN: could not download city dataset; secondary temperature markers will be skipped until this succeeds (re-run install.sh to retry)."
  fi
  rm -rf "$CITIES_TMPDIR"
fi

ln -sf "$PKG_DIR/systemd/weather-globe.service" "$SYSTEMD_DIR/weather-globe.service"
ln -sf "$PKG_DIR/systemd/weather-globe.timer" "$SYSTEMD_DIR/weather-globe.timer"
systemctl --user daemon-reload
systemctl --user enable --now weather-globe.timer

if [[ ! -e "$PLUGINS_DIR/$PLUGIN_ID" ]]; then
  ln -s "$PKG_DIR" "$PLUGINS_DIR/$PLUGIN_ID"
fi

if command -v omarchy-shell &>/dev/null; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

if ! compgen -G "$STATE_DIR/wallpaper-*.png" > /dev/null; then
  echo "Rendering first background (this fetches satellite imagery, may take a bit)..."
  "$PKG_DIR/render.sh" || echo "First render failed; check $STATE_DIR/render.log"
fi

cat <<EOF

Installed:
  - Render script:  $PKG_DIR/render.sh
  - Timer:           weather-globe.timer (every 30 min, systemctl --user)
  - Bar widget:      $PLUGIN_ID (add it to a bar section in shell.json, or
                      run: omarchy bar move $PLUGIN_ID --section right)

Logs: $STATE_DIR/render.log
EOF
