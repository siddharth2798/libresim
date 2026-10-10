#!/usr/bin/env bash
# Fetch Sentinel-2 cloudless (EOX, personal non-commercial use) straight from the
# WMTS, warped to the world frame (local TM, see tools/common.py) at 10 m/px over
# the terrain grid extent. Output: data/raw/imagery/s2.tif (RGB JPEG, tiled)
set -euo pipefail
cd "$(dirname "$0")/.."
LAYER="${LAYER:-s2cloudless-2024_3857}"
OUT=data/raw/imagery/s2.tif
PY="tools/.venv/bin/python -c"
PROJ=$($PY "import sys; sys.path.insert(0,'tools'); import common as c; print(c.WORLD_PROJ)")
EXT=$($PY "import sys; sys.path.insert(0,'tools'); import common as c; print(c.X_MIN, c.Y_MIN, c.X_MAX, c.Y_MAX)")
mkdir -p data/raw/imagery
export GDAL_HTTP_MAX_RETRY=5 GDAL_HTTP_RETRY_DELAY=2 GDAL_CACHEMAX=1024
gdalwarp -overwrite -multi -wo NUM_THREADS=4 \
  -srcband 1 -srcband 2 -srcband 3 -nosrcalpha \
  -t_srs "$PROJ" -tr 10 10 -r cubic -te $EXT \
  -co COMPRESS=JPEG -co JPEG_QUALITY=90 -co PHOTOMETRIC=YCBCR -co TILED=YES -co BIGTIFF=IF_SAFER \
  "WMTS:https://tiles.maps.eox.at/wmts/1.0.0/WMTSCapabilities.xml,layer=${LAYER},tilematrixset=GoogleMapsCompatible" \
  "$OUT"
echo "done: $OUT"
