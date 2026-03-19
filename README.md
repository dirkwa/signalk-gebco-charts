# GEBCO Shaded Relief MBTiles

Pre-built shaded relief MBTiles derived from the [GEBCO Grid](https://www.gebco.net/data_and_products/gridded_bathymetry_data/) for use with [SignalK](https://signalk.org) and [Freeboard-SK](https://github.com/SignalK/freeboard-sk).

GEBCO releases a new grid every year (usually July–August). This repository automatically detects new releases and builds updated MBTiles via GitHub Actions.

## Downloads

See the [Releases](../../releases) page for the latest pre-built files.

| File | Description |
|------|-------------|
| `gebco-YYYY-shaded-relief.zip` | Raster shaded relief (JPEG tiles, z0–z8) |
| `catalog.json` | Machine-readable catalog for the charts provider plugin |

## Usage with SignalK

1. Download the zip file from the latest release
2. Extract the `.mbtiles` file
3. Place it in your SignalK charts directory
4. Restart SignalK — the chart provider will register it automatically

## Warning

GEBCO's 15 arc-second resolution (~450m cells at the equator) is suitable for **offshore passage planning only**. It is **not suitable** for coastal navigation, harbor entry, or anywhere accurate depth information is critical. Always use official nautical charts for navigation.

## Attribution

GEBCO Compilation Group (YEAR) GEBCO YEAR Grid
https://www.gebco.net

The GEBCO Grid is released under **CC-BY 4.0** — you may redistribute and create derivative works but must include attribution. See [GEBCO terms of use](https://www.gebco.net/data_and_products/gridded_bathymetry_data/#a1) for details. The build tooling in this repository is licensed under Apache-2.0.

## How the build works

```
COG on source.coop S3 (4.28 GB Cloud-Optimized GeoTIFF)
    │
    │  GDAL /vsicurl/ streaming (full global extent)
    │
    ├─ gdaldem hillshade     → 3D relief shading
    ├─ gdaldem color-relief  → hypsometric color ramp
    │                          (ocean: navy→cyan, land: green→brown→white)
    │
    └─ gdal_calc.py blend    → hillshade × color → shaded relief
              │
              └─ gdal_translate -of MBTiles → JPEG tiles z0-z8
                       │
                       └─ GitHub Release
```

## Triggering a build manually

```
Actions → Build GEBCO MBTiles → Run workflow → Enter year
```

The weekly check job runs every Monday July–October and automatically triggers a build when it detects a new GEBCO release year on source.coop.
