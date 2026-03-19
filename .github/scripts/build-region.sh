#!/bin/bash
# build-region.sh
# Builds raster shaded relief MBTiles for a single geographic region
# from the GEBCO COG, streaming only the bytes needed.
#
# Usage: build-region.sh <YEAR> <REGION_NAME> <MINX> <MINY> <MAXX> <MAXY>
#
# Example: build-region.sh 2024 global -180 -90 180 90

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
# ---------------------------------------------------------------
echo "[1/4] Streaming region from COG..."
REGION_TIF="$OUTDIR/${REGION}_raw.tif"

gdal_translate \
  -projwin "$MINX" "$MAXY" "$MAXX" "$MINY" \
  -co COMPRESS=DEFLATE \
  -co TILED=YES \
  "$COG_URL" \
  "$REGION_TIF"

echo "      Downloaded: $(du -sh "$REGION_TIF" | cut -f1)"

# ---------------------------------------------------------------
# STEP 2: Generate hillshade for 3D relief effect
# ---------------------------------------------------------------
echo "[2/4] Generating hillshade..."
HILLSHADE_TIF="$OUTDIR/${REGION}_hillshade.tif"

gdaldem hillshade \
  -z 5 \
  -az 315 \
  -alt 45 \
  -co COMPRESS=DEFLATE \
  -co TILED=YES \
  "$REGION_TIF" \
  "$HILLSHADE_TIF"

# ---------------------------------------------------------------
# STEP 3: Apply hypsometric color ramp (ocean + land)
# ---------------------------------------------------------------
echo "[3/4] Applying color relief..."

# Hypsometric color table matching GEBCO style:
# Deep ocean navy → shallow cyan, then green lowlands → brown mountains → white peaks
COLOR_TABLE="$OUTDIR/gebco_colors.txt"
cat > "$COLOR_TABLE" << 'EOF'
nv    0   0   0   0
-11000   8  10  40 255
-8000   10  20  60 255
-6000   14  30  78 255
-4000   18  45 100 255
-2000   24  65 130 255
-1000   35  90 155 255
-500    50 115 175 255
-200    75 140 195 255
-100   100 165 210 255
-50    130 190 225 255
-20    165 215 238 255
-10    195 230 245 255
-1     210 240 250 255
0      172 208 165 255
50     148 191 139 255
200    168 198 143 255
500    189 204 150 255
1000   209 215 171 255
1500   225 228 181 255
2000   239 235 192 255
3000   232 225 182 255
4000   222 198 158 255
5000   211 178 143 255
6000   202 164 130 255
7000   195 152 119 255
8000   189 140 112 255
8850   220 220 220 255
EOF

COLORED_TIF="$OUTDIR/${REGION}_colored.tif"
gdaldem color-relief \
  "$REGION_TIF" \
  "$COLOR_TABLE" \
  "$COLORED_TIF" \
  -co COMPRESS=DEFLATE \
  -co TILED=YES

# Blend hillshade with color relief using gdal_calc
# Formula: color * (hillshade / 255) with slight brightening
BLENDED_TIF="$OUTDIR/${REGION}_blended.tif"
gdal_calc.py \
  --calc="numpy.clip((A * (B / 180.0)), 0, 255).astype(numpy.uint8)" \
  -A "$COLORED_TIF" --A_band=1 \
  -B "$HILLSHADE_TIF" --B_band=1 \
  --outfile="$OUTDIR/${REGION}_r.tif" \
  --type=Byte --co COMPRESS=DEFLATE --co TILED=YES --co BIGTIFF=YES

gdal_calc.py \
  --calc="numpy.clip((A * (B / 180.0)), 0, 255).astype(numpy.uint8)" \
  -A "$COLORED_TIF" --A_band=2 \
  -B "$HILLSHADE_TIF" --B_band=1 \
  --outfile="$OUTDIR/${REGION}_g.tif" \
  --type=Byte --co COMPRESS=DEFLATE --co TILED=YES --co BIGTIFF=YES

gdal_calc.py \
  --calc="numpy.clip((A * (B / 180.0)), 0, 255).astype(numpy.uint8)" \
  -A "$COLORED_TIF" --A_band=3 \
  -B "$HILLSHADE_TIF" --B_band=1 \
  --outfile="$OUTDIR/${REGION}_b.tif" \
  --type=Byte --co COMPRESS=DEFLATE --co TILED=YES --co BIGTIFF=YES

# Merge R, G, B bands via VRT (zero memory — no 28GB allocation)
BLENDED_VRT="$OUTDIR/${REGION}_blended.vrt"
gdalbuildvrt \
  -separate \
  "$BLENDED_VRT" \
  "$OUTDIR/${REGION}_r.tif" \
  "$OUTDIR/${REGION}_g.tif" \
  "$OUTDIR/${REGION}_b.tif"

gdal_translate \
  -co COMPRESS=DEFLATE \
  -co TILED=YES \
  -co BIGTIFF=YES \
  "$BLENDED_VRT" \
  "$BLENDED_TIF"

rm -f "$OUTDIR/${REGION}_r.tif" "$OUTDIR/${REGION}_g.tif" "$OUTDIR/${REGION}_b.tif" "$BLENDED_VRT"

# ---------------------------------------------------------------
# STEP 4: Convert to MBTiles
# ---------------------------------------------------------------
echo "[4/4] Building MBTiles..."

RASTER_MBTILES="$OUTDIR/${REGION}_raster.mbtiles"
gdal_translate \
  -of MBTiles \
  -co TILE_FORMAT=PNG \
  -co ZOOM_LEVEL_STRATEGY=AUTO \
  -co RESAMPLING=AVERAGE \
  "$BLENDED_TIF" \
  "$RASTER_MBTILES"

gdaladdo \
  -r average \
  --config COMPRESS_OVERVIEW DEFLATE \
  "$RASTER_MBTILES" \
  2 4 8 16 32 64 128 256

# Write attribution into MBTiles metadata
sqlite3 "$RASTER_MBTILES" "
  INSERT OR REPLACE INTO metadata VALUES ('name', 'GEBCO ${YEAR} Shaded Relief - ${REGION}');
  INSERT OR REPLACE INTO metadata VALUES ('description', 'Bathymetric and topographic shaded relief derived from GEBCO ${YEAR} Grid');
  INSERT OR REPLACE INTO metadata VALUES ('attribution', 'GEBCO Compilation Group (${YEAR}) GEBCO ${YEAR} Grid (https://www.gebco.net)');
  INSERT OR REPLACE INTO metadata VALUES ('version', '${YEAR}.1');
  INSERT OR REPLACE INTO metadata VALUES ('type', 'baselayer');
  INSERT OR REPLACE INTO metadata VALUES ('format', 'png');
"

echo "      Raster MBTiles: $(du -sh "$RASTER_MBTILES" | cut -f1)"

# ---------------------------------------------------------------
# Cleanup intermediates
# ---------------------------------------------------------------
echo "Cleaning up intermediates..."
rm -f "$REGION_TIF" "$HILLSHADE_TIF" "$COLORED_TIF" "$BLENDED_TIF" "$COLOR_TABLE"

echo "=== Done: $REGION ==="
ls -lh "$OUTDIR/${REGION}_"*.mbtiles
