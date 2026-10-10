#!/usr/bin/env bash
# Outer-ring imagery: Sentinel-2 cloudless at 80 m/px over the outer world box
# (OUTER in tools/common.py, ~490 x 490 km). Output data/raw/imagery/s2_outer.tif
set -euo pipefail
cd "$(dirname "$0")/.."
LAYER="${LAYER:-s2cloudless-2024_3857}"
PY="tools/.venv/bin/python -c"
PROJ=$($PY "import sys; sys.path.insert(0,'tools'); import common as c; print(c.WORLD_PROJ)")
EXT=$($PY "import sys; sys.path.insert(0,'tools'); import common as c; print(*c.OUTER)")
export GDAL_HTTP_MAX_RETRY=12 GDAL_HTTP_RETRY_DELAY=4 GDAL_CACHEMAX=1024 GDAL_DEFAULT_WMS_CACHE_PATH=data/raw/imagery/wmscache
gdalwarp -overwrite -multi -wo NUM_THREADS=4 -srcband 1 -srcband 2 -srcband 3 -nosrcalpha \
  -t_srs "$PROJ" -tr 80 80 -r average -te $EXT \
  -co COMPRESS=JPEG -co JPEG_QUALITY=90 -co PHOTOMETRIC=YCBCR -co TILED=YES -co BIGTIFF=IF_SAFER \
  "WMTS:https://tiles.maps.eox.at/wmts/1.0.0/WMTSCapabilities.xml,layer=${LAYER},tilematrixset=GoogleMapsCompatible" \
  data/raw/imagery/s2_outer.tif
echo "done"
