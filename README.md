# GEBCO Bathymetric MBTiles

Pre-built MBTiles files derived from the [GEBCO Grid](https://www.gebco.net/data_and_products/gridded_bathymetry_data/) for use with [SignalK](https://signalk.org) and [Freeboard-SK](https://github.com/SignalK/freeboard-sk).

GEBCO releases a new grid every year (usually July–August). This repository automatically detects new releases and builds updated MBTiles via GitHub Actions.

## Downloads

See the [Releases](../../releases) page for the latest pre-built files.

| File | Type | Size | Description |
|------|------|------|-------------|
| `gebco-YYYY-depth-shading.zip` | Raster MBTiles (PNG) | ~100–150 MB | Blue depth gradient, z0–z8 |
| `gebco-YYYY-depth-contours.zip` | Vector MBTiles (MVT) | ~400–600 MB | Depth contours + area polygons, z0–z8 |
| `catalog.json` | JSON | tiny | Machine-readable catalog for the plugin |

## Usage with SignalK

1. Download the zip file(s) you need from the latest release
2. Extract the `.mbtiles` file
3. Place it in your SignalK charts directory
4. Restart SignalK — the chart provider will register it automatically

The vector contours file contains two layers:
- **`depth_contours`** — LineStrings with a `depth` attribute (negative meters)
- **`depth_areas`** — Polygons with `DRVAL1` (min depth) and `DRVAL2` (max depth)

These match the S-57 attribute naming convention for use with the same client-side style functions as ENC vector tiles.

## ⚠️ Important

GEBCO's 15 arc-second resolution (~450m cells at the equator) is suitable for **offshore passage planning only**. It is **not suitable** for coastal navigation, harbor entry, or anywhere accurate depth information is critical. Always use official nautical charts for navigation.

## Attribution

GEBCO Compilation Group (YEAR) GEBCO YEAR Grid  
https://www.gebco.net

The GEBCO Grid is released under a permissive license requiring attribution. See [GEBCO terms of use](https://www.gebco.net/data_and_products/gridded_bathymetry_data/#a1) for details.

## How the build works

```
COG on source.coop S3 (4.28 GB Cloud-Optimized GeoTIFF)
    │
    │  GDAL /vsicurl/ streaming — only downloads each region's bytes
    │
    ├─ Pacific region    ──────────────┐
    ├─ Atlantic region   ──(parallel)──┤
    ├─ Indian Ocean E    ──────────────┤
    └─ Indian Ocean W    ──────────────┘
              │
              │  Per-region:
              │  gdaldem color-relief  → raster MBTiles (PNG, z0-z8)
              │  gdal_contour          → depth lines + area polygons
              │  tippecanoe            → vector MBTiles (MVT, z0-z8)
              │
              └─ tile-join merge → global files → GitHub Release
```

The COG streaming means no 4GB+ download — each region job only downloads the bytes it needs.

## Triggering a build manually

```
Actions → Build GEBCO MBTiles → Run workflow → Enter year
```

The weekly check job runs every Monday July–October and automatically triggers a build when it detects a new GEBCO release year on source.coop.
