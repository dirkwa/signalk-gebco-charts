#!/bin/bash
# build-region.sh
# Builds raster and vector MBTiles for a single geographic region
# from the GEBCO COG, streaming only the bytes needed.
#
# Usage: build-region.sh <YEAR> <REGION_NAME> <MINX> <MINY> <MAXX> <MAXY>
#
# Example: build-region.sh 2024 pacific -180 -80 -60 80

set -euo pipefail

YEAR="$1"
REGION="$2"
MINX="$3"   # West longitude
MINY="$4"   # South latitude
MAXX="$5"   # East longitude
MAXY="$6"   # North latitude

OUTDIR="${OUTDIR:-/tmp/gebco-output}"
mkdir -p "$OUTDIR"

COG_URL="/vsicurl/https://s3.us-west-2.amazonaws.com/us-west-2.opendata.source.coop/alexgleith/gebco-${YEAR}/GEBCO_${YEAR}.tif"

# GDAL streaming config: retry on failure, reasonable timeout
export GDAL_HTTP_FETCH_RETRY=5
export GDAL_HTTP_TIMEOUT=120
export GDAL_HTTP_MAX_RETRY=5
export CPL_VSIL_USE_TEMP_FILE_FOR_RANDOM_WRITE=YES

echo "=== Region: $REGION ($MINX,$MINY → $MAXX,$MAXY) ==="

# ---------------------------------------------------------------
# STEP 1: Stream the region from the COG into a local GeoTIFF
# This is the only "download" - only the bytes for this bounding
# box are transferred, not the full 4GB file.
# ---------------------------------------------------------------
echo "[1/5] Streaming region from COG..."
REGION_TIF="$OUTDIR/${REGION}_raw.tif"

gdal_translate \
  -projwin "$MINX" "$MAXY" "$MAXX" "$MINY" \
  -co COMPRESS=DEFLATE \
  -co TILED=YES \
  "$COG_URL" \
  "$REGION_TIF"

echo "      Downloaded: $(du -sh "$REGION_TIF" | cut -f1)"

# ---------------------------------------------------------------
# STEP 2: RASTER — Depth shading → PNG MBTiles
# Nautical color ramp: deep navy → shallow cyan → transparent land
# ---------------------------------------------------------------
echo "[2/5] Building raster depth shading..."

# Nautical color table (depth in meters → RGBA)
# Only covers negative values (ocean); land becomes transparent
COLOR_TABLE="$OUTDIR/nautical_depths.txt"
cat > "$COLOR_TABLE" << 'EOF'
nv    0   0   0   0
-11000   0   0  40 255
-5000    0  20  80 255
-2000    0  50 120 255
-1000    0  80 160 255
-500    20 110 185 255
-200    40 140 200 255
-100    70 165 215 255
-50    100 185 228 255
-20    140 208 238 255
-10    175 225 245 255
-5     205 237 250 255
-2     225 244 252 255
0        0   0   0   0
EOF

COLORED_TIF="$OUTDIR/${REGION}_colored.tif"
gdaldem color-relief \
  -alpha \
  -nearest_color_entry \
  "$REGION_TIF" \
  "$COLOR_TABLE" \
  "$COLORED_TIF"

# Convert to raster MBTiles (PNG tiles)
# Max zoom z8 — GEBCO's 15 arc-second resolution = ~450m, useful to z9 at most
RASTER_MBTILES="$OUTDIR/${REGION}_raster.mbtiles"
gdal_translate \
  -of MBTiles \
  -co TILE_FORMAT=PNG \
  -co ZOOM_LEVEL_STRATEGY=AUTO \
  -co RESAMPLING=AVERAGE \
  "$COLORED_TIF" \
  "$RASTER_MBTILES"

gdaladdo \
  -r average \
  --config COMPRESS_OVERVIEW DEFLATE \
  "$RASTER_MBTILES" \
  2 4 8 16 32 64 128 256

# Write attribution into MBTiles metadata
sqlite3 "$RASTER_MBTILES" "
  INSERT OR REPLACE INTO metadata VALUES ('name', 'GEBCO ${YEAR} Depth Shading - ${REGION}');
  INSERT OR REPLACE INTO metadata VALUES ('description', 'Bathymetric depth shading derived from GEBCO ${YEAR} Grid');
  INSERT OR REPLACE INTO metadata VALUES ('attribution', 'GEBCO Compilation Group (${YEAR}) GEBCO ${YEAR} Grid (https://www.gebco.net)');
  INSERT OR REPLACE INTO metadata VALUES ('version', '${YEAR}.1');
  INSERT OR REPLACE INTO metadata VALUES ('type', 'overlay');
  INSERT OR REPLACE INTO metadata VALUES ('format', 'png');
"

echo "      Raster MBTiles: $(du -sh "$RASTER_MBTILES" | cut -f1)"

# ---------------------------------------------------------------
# STEP 3: VECTOR — Depth contours + areas → vector MBTiles
# ---------------------------------------------------------------
echo "[3/5] Extracting depth contours..."

# Downsample to 60 arcseconds (~1.8km) before contouring.
# At z8 each tile covers ~1.4°, so 15-arcsecond resolution is wildly
# oversampled. Downsampling 4x makes contouring ~16x faster with
# no visible difference at the target zoom levels.
OCEAN_LOWRES="$OUTDIR/${REGION}_ocean_lowres.tif"
gdalwarp \
  -tr 0.016666667 0.016666667 \
  -r average \
  -co COMPRESS=DEFLATE \
  -co TILED=YES \
  "$REGION_TIF" \
  "$OCEAN_LOWRES"

# Mask land (positive values) to nodata
OCEAN_TIF="$OUTDIR/${REGION}_ocean.tif"
gdal_calc.py \
  -A "$OCEAN_LOWRES" \
  --outfile="$OCEAN_TIF" \
  --calc="numpy.where(A < 0, A, 32767)" \
  --NoDataValue=32767 \
  --type=Int16 \
  --co COMPRESS=DEFLATE

# Contour lines — nautical depth intervals
CONTOUR_LINES_GEOJSON="$OUTDIR/${REGION}_contour_lines.geojson"
gdal_contour \
  -f GeoJSON \
  -fl -5 -10 -20 -30 -50 -100 -200 -500 -1000 -2000 -3000 -5000 \
  -a depth \
  -snodata 32767 \
  "$OCEAN_TIF" \
  "$CONTOUR_LINES_GEOJSON"

# Depth area polygons — for depth-band shading in the client
CONTOUR_POLY_RAW="$OUTDIR/${REGION}_contour_poly_raw.geojson"
gdal_contour \
  -f GeoJSON \
  -fl -5 -10 -20 -30 -50 -100 -200 -500 -1000 -2000 -3000 -5000 \
  -p \
  -amin DRVAL1 \
  -amax DRVAL2 \
  -snodata 32767 \
  "$OCEAN_TIF" \
  "$CONTOUR_POLY_RAW"

# Fix invalid geometry (non-closed rings) from gdal_contour
CONTOUR_POLY_GEOJSON="$OUTDIR/${REGION}_contour_poly.geojson"
ogr2ogr \
  -f GeoJSON \
  -makevalid \
  "$CONTOUR_POLY_GEOJSON" \
  "$CONTOUR_POLY_RAW"
rm -f "$CONTOUR_POLY_RAW"

echo "[4/5] Building vector MBTiles with tippecanoe..."

VECTOR_MBTILES="$OUTDIR/${REGION}_vector.mbtiles"

tippecanoe \
  --output="$VECTOR_MBTILES" \
  --minimum-zoom=0 \
  --maximum-zoom=8 \
  --drop-densest-as-needed \
  --coalesce-densest-as-needed \
  --extend-zooms-if-still-dropping \
  --simplification=10 \
  --force \
  --layer=depth_areas    "$CONTOUR_POLY_GEOJSON" \
  --layer=depth_contours "$CONTOUR_LINES_GEOJSON"

# Inject metadata
sqlite3 "$VECTOR_MBTILES" "
  INSERT OR REPLACE INTO metadata VALUES ('name', 'GEBCO ${YEAR} Depth Contours - ${REGION}');
  INSERT OR REPLACE INTO metadata VALUES ('description', 'Bathymetric depth contours and areas derived from GEBCO ${YEAR} Grid');
  INSERT OR REPLACE INTO metadata VALUES ('attribution', 'GEBCO Compilation Group (${YEAR}) GEBCO ${YEAR} Grid (https://www.gebco.net)');
  INSERT OR REPLACE INTO metadata VALUES ('version', '${YEAR}.1');
  INSERT OR REPLACE INTO metadata VALUES ('type', 'overlay');
  INSERT OR REPLACE INTO metadata VALUES ('format', 'pbf');
"

echo "      Vector MBTiles: $(du -sh "$VECTOR_MBTILES" | cut -f1)"

# ---------------------------------------------------------------
# STEP 5: Cleanup intermediates, keep only final MBTiles
# ---------------------------------------------------------------
echo "[5/5] Cleaning up intermediates..."
rm -f "$REGION_TIF" "$COLORED_TIF" "$OCEAN_LOWRES" "$OCEAN_TIF" \
      "$CONTOUR_LINES_GEOJSON" "$CONTOUR_POLY_GEOJSON" \
      "$COLOR_TABLE"

echo "=== Done: $REGION ==="
ls -lh "$OUTDIR/${REGION}_"*.mbtiles
