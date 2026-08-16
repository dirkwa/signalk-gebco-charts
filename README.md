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

The GEBCO Grid is released under **CC-BY 4.0** — you may redistribute and create derivative works but must include attribution. See [GEBCO terms of use](https://www.gebco.net/data_and_products/gridded_bathymetry_data/#a1) for details. The build tooling in this repository is licensed separately — see [License](#license) below.

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

## License

**Data:** the published MBTiles are derived from the GEBCO Grid and remain under
GEBCO's **CC-BY 4.0** terms (see [Attribution](#attribution)). Nothing below
restricts them.

**Build tooling** (the workflows and scripts in this repository) is
**source available, not open source**. See [LICENSE.md](LICENSE.md).

**You may**, free of charge: run it for your own boat, fleet or company; modify
it for your own use; use it in education and research; and provide professional
services around it.

**You may not**: redistribute the tooling, or publish a modified version of it.
Verbatim copies of official releases may be mirrored and cached.

The tooling as of commit 708a1b5 and earlier remains available under Apache-2.0,
see [LICENSE-Apache-2.0-through-2026-08.txt](LICENSE-Apache-2.0-through-2026-08.txt).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
