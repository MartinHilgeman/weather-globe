#!/bin/bash
# Renders an xplanet-style Earth wallpaper using real satellite cloud imagery
# (NASA GIBS VIIRS true-color) with live global precipitation/storm data
# (NASA GIBS IMERG) overlaid, then sets it as the Omarchy desktop background.
set -uo pipefail

STATE_DIR="$HOME/.local/state/omarchy/weather-globe"
CONFIG_DIR="$HOME/.config/omarchy/weather-globe"
LOG="$STATE_DIR/render.log"
mkdir -p "$STATE_DIR"

# Keep the log from growing forever (it's read by the bar widget on every run).
if [[ -f $LOG ]]; then
  tail -n 400 "$LOG" > "$LOG.trimmed" && mv "$LOG.trimmed" "$LOG"
fi

exec >>"$LOG" 2>&1
echo "=== $(date -u -Iseconds) ==="

FETCH_WIDTH=2600
FETCH_HEIGHT=1300
OUT_GEOMETRY="${WEATHER_GLOBE_GEOMETRY:-3840x2160}"
GIBS="https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi"

TODAY=$(date -u +%Y-%m-%d)
YESTERDAY=$(date -u -d "yesterday" +%Y-%m-%d)

TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fetch() {
  local layer=$1 time=$2 out=$3 bbox=$4
  curl -fsSL --max-time 30 -o "$out" \
    "$GIBS?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=${layer}&SRS=EPSG:4326&BBOX=${bbox}&WIDTH=${FETCH_WIDTH}&HEIGHT=${FETCH_HEIGHT}&FORMAT=image/png&TIME=${time}"
}

# --- Projection: read the user's choice (set via the bar widget), falling
# --- back to xplanet's classic default view if unset or invalid.
VALID_PROJECTIONS=(ancient azimuthal bonne equal_area gnomonic hemisphere lambert mercator mollweide orthographic peters polyconic rectangular tsc)
PROJECTION=""
if [[ -f "$STATE_DIR/projection" ]]; then
  PROJECTION=$(<"$STATE_DIR/projection")
fi
if [[ -n $PROJECTION ]]; then
  valid=0
  for v in "${VALID_PROJECTIONS[@]}"; do
    [[ $v == "$PROJECTION" ]] && valid=1 && break
  done
  [[ $valid -eq 1 ]] || { echo "WARN: unknown projection '$PROJECTION' in state file, using default"; PROJECTION=""; }
fi

# --- Zoom to current location: reads the same weather location the bar's
# --- weather widget uses (~/.local/state/omarchy/settings/weather.json),
# --- falling back to a name/IP lookup via wttr.in (the same free, keyless
# --- service omarchy-weather-location already relies on).
ZOOM=""
[[ -f "$STATE_DIR/zoom-location" ]] && ZOOM=$(<"$STATE_DIR/zoom-location")

USE_ZOOM=0
LAT="" LON=""
if [[ $ZOOM == "1" ]]; then
  WEATHER_JSON="$HOME/.local/state/omarchy/settings/weather.json"
  if [[ -f $WEATHER_JSON ]]; then
    LAT=$(jq -r '.latitude // empty' "$WEATHER_JSON" 2>/dev/null)
    LON=$(jq -r '.longitude // empty' "$WEATHER_JSON" 2>/dev/null)
  fi
  if [[ -z $LAT || -z $LON ]]; then
    NAME=""
    [[ -f $WEATHER_JSON ]] && NAME=$(jq -r '.name // empty' "$WEATHER_JSON" 2>/dev/null)
    QUERY="https://wttr.in/?format=j1"
    [[ -n $NAME ]] && QUERY="https://wttr.in/${NAME// /+}?format=j1"
    if WTTR_JSON=$(curl -fsS --max-time 8 "$QUERY" 2>/dev/null); then
      LAT=$(echo "$WTTR_JSON" | jq -r '.nearest_area[0].latitude // empty' 2>/dev/null)
      LON=$(echo "$WTTR_JSON" | jq -r '.nearest_area[0].longitude // empty' 2>/dev/null)
    fi
  fi
  if [[ -n $LAT && -n $LON ]]; then
    USE_ZOOM=1
  else
    echo "WARN: could not resolve current location for zoom; rendering full globe instead"
  fi
fi

# --- Regional bbox around the location: ~28 degrees of latitude tall,
# --- longitude span widened toward the poles so it covers a roughly
# --- constant physical width. Computed whenever zoom is on so it's
# --- available both for the flat-projection image fetch below AND for
# --- filtering nearby temperature markers, regardless of projection.
if [[ $USE_ZOOM -eq 1 ]]; then
  read -r NORTH SOUTH WEST EAST <<<"$(awk -v lat="$LAT" -v lon="$LON" 'BEGIN {
    latspan = 14
    lonspan = 20 / cos(lat * 3.14159265 / 180)
    if (lonspan > 60) lonspan = 60
    north = lat + latspan; if (north > 90) north = 90
    south = lat - latspan; if (south < -90) south = -90
    west = lon - lonspan; if (west < -180) west = -180
    east = lon + lonspan; if (east > 180) east = 180
    printf "%.3f %.3f %.3f %.3f", north, south, west, east
  }')"
fi

# Rectangular and azimuthal are real "flat map" projections that can be
# cropped to a region and still look correct; xplanet's other projections
# either assume full-globe framing (Mollweide, Peters, Bonne, ...) or, in
# Mercator's case, are permanently centered on the equator with no way to
# recenter on an arbitrary latitude -- so a 52N location can never appear
# "zoomed" in it. For those, zoom falls back to the classic close-orbit 3D
# camera view (ignoring the projection choice), same as before.
ZOOM_FLAT=0
if [[ $USE_ZOOM -eq 1 && ($PROJECTION == "rectangular" || $PROJECTION == "azimuthal") ]]; then
  ZOOM_FLAT=1
fi

BBOX="-180,-90,180,90"
[[ $ZOOM_FLAT -eq 1 ]] && BBOX="${WEST},${SOUTH},${EAST},${NORTH}"

# --- Temperature markers: the user's own location plus a few nearby
# --- notable cities, labeled on the map. Only meaningful while zoomed in
# --- (a label on the full unzoomed globe would be illegibly small), so
# --- this is entirely skipped when zoom is off.
MARKER_FILE=""
rm -f "$STATE_DIR/temp-markers.txt"
SHOW_TEMP=""
[[ -f "$STATE_DIR/show-temperature" ]] && SHOW_TEMP=$(<"$STATE_DIR/show-temperature")

if [[ $USE_ZOOM -eq 1 && $SHOW_TEMP == "1" ]]; then
  MARKERS_TMP="$TMP/markers.txt"
  : > "$MARKERS_TMP"

  PRIMARY_NAME=""
  [[ -f $WEATHER_JSON ]] && PRIMARY_NAME=$(jq -r '.name // empty' "$WEATHER_JSON" 2>/dev/null)

  # Kick off the primary lookup (only if location resolution above didn't
  # already fetch one) and all secondary-city lookups in parallel -- these
  # are fully independent wttr.in calls, and running them one at a time was
  # the single biggest render-time cost once more than a couple of markers
  # are shown.
  PRIMARY_PID=""
  if [[ -z "${WTTR_JSON:-}" ]]; then
    curl -fsS --max-time 8 -o "$TMP/wttr_primary.json" "https://wttr.in/${LAT},${LON}?format=j1" &
    PRIMARY_PID=$!
  fi

  # Secondary: nearby notable cities from the bundled GeoNames dataset,
  # filtered to the same region as zoom, top 8 by population, excluding
  # anything within ~0.3 degrees of the primary location. No explicit
  # align= on any marker (primary included) so xplanet spreads overlapping
  # labels apart automatically -- important now that there are enough
  # markers to collide in a crowded region.
  CITIES_DB="$STATE_DIR/cities15000.txt"
  SEC_PIDS=()
  SEC_NAMES=()
  SEC_LATS=()
  SEC_LONS=()
  if [[ -f $CITIES_DB ]]; then
    CANDIDATES=$(awk -F'\t' -v n="$NORTH" -v s="$SOUTH" -v w="$WEST" -v e="$EAST" \
        -v plat="$LAT" -v plon="$LON" '
      BEGIN { OFS="\t" }
      {
        name = $3   # asciiname: avoids non-Latin scripts in the label
        lat = $5 + 0; lon = $6 + 0; pop = $15 + 0
        if (name == "" || $5 == "" || $6 == "") next
        if (lat < s || lat > n || lon < w || lon > e) next
        dlat = lat - plat; if (dlat < 0) dlat = -dlat
        dlon = lon - plon; if (dlon < 0) dlon = -dlon
        if (dlat < 0.3 && dlon < 0.3) next
        gsub(/"/, "", name)
        print pop, name, lat, lon
      }' "$CITIES_DB" | sort -t$'\t' -k1,1 -rn | head -n 8)

    i=0
    while IFS=$'\t' read -r _ CNAME CLAT CLON; do
      [[ -z $CNAME ]] && continue
      curl -fsS --max-time 8 -o "$TMP/wttr_sec_$i.json" "https://wttr.in/${CLAT},${CLON}?format=j1" &
      SEC_PIDS+=("$!")
      SEC_NAMES+=("$CNAME")
      SEC_LATS+=("$CLAT")
      SEC_LONS+=("$CLON")
      i=$((i + 1))
    done <<<"$CANDIDATES"
  else
    echo "WARN: city dataset not found at $CITIES_DB; skipping secondary temperature markers"
  fi

  [[ -n $PRIMARY_PID ]] && wait "$PRIMARY_PID"
  for pid in "${SEC_PIDS[@]}"; do wait "$pid"; done

  # Primary: reuse the wttr.in response from location resolution above if
  # one was already made (weather.json lacked lat/lon), otherwise read the
  # dedicated lookup just fired above.
  PRIMARY_TEMP=""
  if [[ -n "${WTTR_JSON:-}" ]]; then
    PRIMARY_TEMP=$(echo "$WTTR_JSON" | jq -r '.current_condition[0].temp_C // empty' 2>/dev/null)
    [[ -z $PRIMARY_NAME ]] && PRIMARY_NAME=$(echo "$WTTR_JSON" | jq -r '.nearest_area[0].areaName[0].value // empty' 2>/dev/null)
  elif [[ -s "$TMP/wttr_primary.json" ]]; then
    PRIMARY_TEMP=$(jq -r '.current_condition[0].temp_C // empty' "$TMP/wttr_primary.json" 2>/dev/null)
    [[ -z $PRIMARY_NAME ]] && PRIMARY_NAME=$(jq -r '.nearest_area[0].areaName[0].value // empty' "$TMP/wttr_primary.json" 2>/dev/null)
  fi

  if [[ -n $PRIMARY_TEMP ]]; then
    [[ -z $PRIMARY_NAME ]] && PRIMARY_NAME="Here"
    echo "${LAT} ${LON} \"${PRIMARY_NAME} ${PRIMARY_TEMP}°C\" color=yellow fontsize=64" >> "$MARKERS_TMP"
  else
    echo "WARN: could not resolve primary temperature; skipping primary marker"
  fi

  for i in "${!SEC_NAMES[@]}"; do
    CTEMP=""
    [[ -s "$TMP/wttr_sec_$i.json" ]] && CTEMP=$(jq -r '.current_condition[0].temp_C // empty' "$TMP/wttr_sec_$i.json" 2>/dev/null)
    if [[ -n $CTEMP ]]; then
      echo "${SEC_LATS[$i]} ${SEC_LONS[$i]} \"${SEC_NAMES[$i]} ${CTEMP}°C\" color=yellow fontsize=46" >> "$MARKERS_TMP"
    else
      echo "WARN: no temperature for secondary marker '${SEC_NAMES[$i]}'; skipping"
    fi
  done

  if [[ -s $MARKERS_TMP ]]; then
    mv "$MARKERS_TMP" "$STATE_DIR/temp-markers.txt"
    MARKER_FILE="temp-markers.txt"
  else
    echo "WARN: no temperature markers resolved; rendering zoom without markers"
  fi
fi

# --- Base cloud imagery + precipitation: fire every GIBS request at once
# --- (VIIRS yesterday/today, and every IMERG time candidate) since they're
# --- all independent fetches -- this was the other big sequential cost,
# --- especially the IMERG walk-back which could chain up to 8 requests.
fetch VIIRS_SNPP_CorrectedReflectance_TrueColor "$YESTERDAY" "$TMP/base_yesterday.png" "$BBOX" &
YESTERDAY_PID=$!
fetch VIIRS_SNPP_CorrectedReflectance_TrueColor "$TODAY" "$TMP/base_today.png" "$BBOX" &
TODAY_PID=$!

IMERG_HOURS=(3 6 9 12 15 18 21 24)
IMERG_PIDS=()
for HRS in "${IMERG_HOURS[@]}"; do
  T=$(date -u -d "$HRS hours ago" +%Y-%m-%dT%H:%M:00Z)
  # round down to the nearest 30 minutes
  MIN=$(date -u -d "$T" +%M)
  T=$(date -u -d "$T -$((10#$MIN % 30)) minutes" +%Y-%m-%dT%H:%M:00Z)
  fetch IMERG_Precipitation_Rate_30min "$T" "$TMP/precip_$HRS.png" "$BBOX" &
  IMERG_PIDS+=("$!")
done

wait "$YESTERDAY_PID"; YESTERDAY_OK=$?
wait "$TODAY_PID"; TODAY_OK=$?
for pid in "${IMERG_PIDS[@]}"; do wait "$pid"; done

if [[ $YESTERDAY_OK -ne 0 ]]; then
  echo "ERROR: failed to fetch base true-color imagery; keeping previous background"
  exit 1
fi

if [[ $TODAY_OK -eq 0 && $(stat -c%s "$TMP/base_today.png" 2>/dev/null || echo 0) -gt 20000 ]]; then
  magick "$TMP/base_yesterday.png" \( "$TMP/base_today.png" -fuzz 1% -transparent black \) \
    -compose over -composite "$TMP/clouds.png"
else
  cp "$TMP/base_yesterday.png" "$TMP/clouds.png"
fi

# Walk the same preference order as before (freshest first) to pick the
# first candidate that actually came back with real data.
PRECIP=""
for HRS in "${IMERG_HOURS[@]}"; do
  if [[ $(stat -c%s "$TMP/precip_$HRS.png" 2>/dev/null || echo 0) -gt 20000 ]]; then
    PRECIP="$TMP/precip_$HRS.png"
    break
  fi
done

if [[ -n "$PRECIP" ]]; then
  # Boost saturation/contrast so heavier (storm-intensity) precipitation
  # cells stand out clearly against the cloud texture.
  magick "$TMP/clouds.png" \( "$PRECIP" -modulate 100,170,100 \) \
    -compose over -composite "$TMP/earth_map.jpg"
else
  echo "WARN: no recent IMERG precipitation frame found; rendering clouds only"
  cp "$TMP/clouds.png" "$TMP/earth_map.jpg"
fi

mv "$TMP/earth_map.jpg" "$STATE_DIR/earth_map.jpg"

XPLANET_ARGS=(
  -searchdir "$STATE_DIR"
  -num_times 1
  -geometry "$OUT_GEOMETRY"
  -output "$TMP/wallpaper.png"
  -quality 100
  -background black
)

if [[ $USE_ZOOM -eq 1 ]]; then
  # A regional map=/mapbounds= config generated for this render only: with
  # the map's bounds matching what was actually fetched above, xplanet crops
  # the flat projection to just that region instead of the whole globe.
  # marker_file= (temperature labels) is added the same way whenever any
  # were resolved above, regardless of which zoom sub-mode is in play.
  ZOOM_CONFIG="$TMP/xplanet-zoom.config"
  {
    echo '[earth]'
    echo '"Earth"'
    echo 'map=earth_map.jpg'
    echo 'night_map=/usr/share/xplanet/images/night.jpg'
    echo 'shade=25'
    echo 'twilight=8'
    echo 'min_radius_for_label=0'
    if [[ $ZOOM_FLAT -eq 1 ]]; then
      echo "mapbounds={$NORTH,$WEST,$SOUTH,$EAST}"
      echo 'color={8,16,32}'
    fi
    [[ -n $MARKER_FILE ]] && echo "marker_file=$MARKER_FILE"
  } > "$ZOOM_CONFIG"

  XPLANET_ARGS+=(-config "$ZOOM_CONFIG")
  if [[ $ZOOM_FLAT -eq 1 ]]; then
    XPLANET_ARGS+=(-projection "$PROJECTION")
    # Rectangular already fills the frame from mapbounds alone; azimuthal
    # needs a much bigger radius to scale the cropped region to fill the canvas.
    [[ $PROJECTION == "azimuthal" ]] && XPLANET_ARGS+=(-latitude "$LAT" -longitude "$LON" -radius 500)
  else
    # Classic close-orbit 3D camera, hovering above the location. Used for
    # zoom + any projection that can't be sensibly cropped to a region.
    XPLANET_ARGS+=(-origin above -latitude "$LAT" -longitude "$LON" -range 1.5)
  fi
else
  XPLANET_ARGS+=(-config "$CONFIG_DIR/xplanet.config")
  [[ -n $PROJECTION ]] && XPLANET_ARGS+=(-projection "$PROJECTION")
fi

# --- Render the globe with xplanet: real current sun angle/terminator,
# --- night-side city lights, starfield.
if ! xplanet "${XPLANET_ARGS[@]}"; then
  echo "ERROR: xplanet render failed"
  exit 1
fi

# Give each render a unique filename. The shell's background plugin skips
# the visual refresh when the new path string equals the currently-displayed
# one (see Background.qml transitionBackground's `finalPath === currentBackground`
# guard) -- reusing a fixed "wallpaper.png" name meant every re-render after
# the first silently never appeared on screen, even though the file and the
# state symlink were both correctly updated underneath.
OUT="$STATE_DIR/wallpaper-$(date -u +%s).png"
mv "$TMP/wallpaper.png" "$OUT"
omarchy-theme-bg-set "$OUT"

# Prune old renders, keeping the one just set plus one prior as a fallback.
find "$STATE_DIR" -maxdepth 1 -name 'wallpaper-*.png' ! -name "$(basename "$OUT")" -printf '%T@ %p\n' \
  | sort -rn | tail -n +2 | cut -d' ' -f2- | xargs -r rm -f

echo "OK: background updated ($(basename "$OUT"))"
