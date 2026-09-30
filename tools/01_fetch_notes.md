# M0 — Data downloads (manual, save into data/raw/)
Region: 18.30N–19.30N, 72.75E–74.10E (Mumbai–Pune)

1. **DEM — Copernicus GLO-30**: https://dataspace.copernicus.eu (free account) or
   AWS open bucket `s3://copernicus-dem-30m/` (no account):
   tiles N18_00_E072, N18_00_E073, N19_00_E072, N19_00_E073 (Copernicus_DSM_COG_10_*_DEM.tif) → data/raw/dem/
2. **Imagery — Sentinel-2 cloudless**: https://s2maps.eu → use its WMTS in QGIS,
   export the bbox at 10 m/px as GeoTIFF (EPSG:32643) → data/raw/imagery/s2.tif
3. **OSM**: https://download.geofabrik.de/asia/india/western-zone.html → western-zone-latest.osm.pbf → data/raw/osm/
4. **Airports/navaids**: https://ourairports.com/data/ → airports.csv, runways.csv, navaids.csv, airport-frequencies.csv → data/raw/ourairports/
5. **JSBSim C172**: https://github.com/JSBSim-Team/jsbsim → aircraft/c172p/ and engine/ (eng_io360c, prop_75in2f) → data/raw/jsbsim/

## Software (Pop!_OS)
sudo apt install gdal-bin python3-gdal qgis blender git
Godot 4 (latest stable, standard build): https://godotengine.org/download/linux  (or Flatpak org.godotengine.Godot)
pip install --user rasterio numpy osmium jsbsim
