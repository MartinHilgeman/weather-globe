# Weather Globe

An xplanet-style desktop background for Omarchy: a full-disk Earth render
using real satellite cloud imagery (NASA GIBS VIIRS true-color) with live
global precipitation/storm data (NASA GIBS IMERG) overlaid, lit by the real
current sun angle (day/night terminator, night-side city lights). Refreshes
automatically every 30 minutes.

## Install

```bash
~/.config/omarchy/weather-globe/install.sh
```

This installs `xplanet` + `imagemagick` + `unzip`, downloads a one-time
~8MB city dataset used for temperature markers (see below), enables a
systemd `--user` timer that re-renders the background every 30 minutes,
and registers a bar widget (`<you>.weather-globe`) showing when it last
refreshed — click it to refresh on demand. Add the widget to your bar
with:

```bash
omarchy bar move $(id -un).weather-globe --section right
```

## Uninstall

```bash
~/.config/omarchy/weather-globe/uninstall.sh
```

## Projection and zoom

The bar widget's panel has a Projection dropdown (all 14 of xplanet's
projection types) and a "Zoom to location" toggle that centers/crops the
render on the location your weather widget uses
(`~/.local/state/omarchy/settings/weather.json`, falling back to a wttr.in
lookup). How they combine:

- **Rectangular** or **Azimuthal** + zoom: a real cropped regional map in
  that projection style (a separate, smaller-area NASA fetch at higher
  effective detail than the full-globe image).
- Any other projection + zoom: falls back to the classic close-orbit 3D
  globe view, centered/zoomed on the location. Mercator specifically can't
  be recentered off the equator in xplanet, so it can never show a location
  at non-equatorial latitudes zoomed in — that's why it's excluded from the
  first case.

Both settings persist in `~/.local/state/omarchy/weather-globe/` (`projection`,
`zoom-location`) via `set-projection.sh` / `set-zoom.sh`, which `render.sh`
reads on every run.

## Temperature markers

A "Show temperature" toggle (only meaningful while Zoom to location is
also on) labels your weather location plus up to 3 nearby notable cities
that fall within the current zoomed view, in the format `<City> <Temp>°C`
— e.g. "Amstelveen 18°C". Temperatures come from wttr.in (the same free,
keyless service used for zoom's location lookup); the nearby cities come
from a bundled GeoNames dataset (`cities15000.txt`, population > 15,000 or
capitals, downloaded once at install time). If the dataset is missing or a
lookup fails, the affected marker is silently skipped (logged as a `WARN`
in render.log) rather than failing the whole render — you'll just see
fewer labels.

Persisted the same way as the other settings, via `set-temperature.sh` →
`~/.local/state/omarchy/weather-globe/show-temperature`.

## Layout

```
render.sh              # fetch imagery, composite, render with xplanet, set background
xplanet.config         # xplanet earth body config (day/night maps)
set-projection.sh      # persists the Projection dropdown choice
set-zoom.sh            # persists the Zoom to location toggle
set-temperature.sh     # persists the Show temperature toggle
systemd/                # user service + timer, symlinked into ~/.config/systemd/user
plugin/                 # bar widget (manifest.json + WeatherGlobe.qml), symlinked into
                        # ~/.config/omarchy/plugins/<you>.weather-globe
```

Rendered output, the composited source imagery, `render.log`, the
GeoNames city dataset (`cities15000.txt`), and the generated
`temp-markers.txt` all live in `~/.local/state/omarchy/weather-globe/`.

## Notes

- Cloud texture is NASA's daily global composite, freshened with whatever of
  today's satellite pass is available yet — so it's usually a few hours to
  ~1 day old where coverage hasn't updated. The precipitation/storm overlay
  (IMERG) is fresher, typically 4-6 hours behind real time (its own latency).
- No API key or account needed; both data sources are free and keyless.
