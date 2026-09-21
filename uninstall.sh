#!/bin/bash
# Removes the Weather Globe plugin's timer, systemd units, and bar widget
# registration. Leaves this package directory and ~/.local/state/omarchy/weather-globe
# (rendered images, logs) in place — delete those yourself if you want them gone too.
set -euo pipefail

PLUGIN_ID="${USER:-$(id -un)}.weather-globe"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
SYSTEMD_DIR="$HOME/.config/systemd/user"

systemctl --user disable --now weather-globe.timer 2>/dev/null || true
rm -f "$SYSTEMD_DIR/weather-globe.service" "$SYSTEMD_DIR/weather-globe.timer"
systemctl --user daemon-reload

rm -f "$PLUGINS_DIR/$PLUGIN_ID"

if command -v omarchy-shell &>/dev/null; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

echo "Weather Globe plugin uninstalled. Package files and render state left untouched."
