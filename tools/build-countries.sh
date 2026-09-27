#!/usr/bin/env bash
# Rebuilds assets/countries.json from Natural Earth 1:50m Admin 0 countries
# (public domain). Dev-time only; needs curl, ogr2ogr (gdal) and jq.
# Output: [{c: ISO-A2, n: name, r: [[lon,lat,lon,lat,...], ...outer rings]}]
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/ne.geojson" \
  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
ogr2ogr -f GeoJSON "$tmp/s.geojson" "$tmp/ne.geojson" -simplify 0.05 \
  -select ISO_A2_EH,NAME -lco COORDINATE_PRECISION=2
jq -c '[.features[]
  | {c: (.properties.ISO_A2_EH | if . == "-99" then "" else . end), n: .properties.NAME,
     r: [(if .geometry.type == "Polygon" then [.geometry.coordinates] else .geometry.coordinates end)[]
         | .[0] | select(length >= 4) | [.[][]]]}
  | select(.r | length > 0)]
  # Territories sharing a code (AU, FR, ...) merge into one entry named after
  # the biggest part; disputed "-99" areas stay separate and unclickable.
  | (map(select(.c == "")) + (map(select(.c != "")) | group_by(.c)
     | map(max_by(.r | map(length) | add) as $main | {c: $main.c, n: $main.n, r: (map(.r[]))})))
  | sort_by(.c)' "$tmp/s.geojson" > assets/countries.json
echo "assets/countries.json: $(jq length assets/countries.json) countries, $(stat -c %s assets/countries.json) bytes"
