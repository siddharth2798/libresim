"""OurAirports CSV -> data/processed/airports.json, navaids.json (world metres + lat/lon).
Covers both regions: the Mumbai-Pune BBOX and the Konkan-Kerala corridor (osm_regions)."""
import csv
import json

import common as c
import osm_regions as R

FT = 0.3048
NAVAID_PAD_DEG = 1.0  # keep VORs/NDBs a little beyond the map (radio range)


def read(name):
    with open(c.RAW / "ourairports" / f"{name}.csv", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def num(s, default=None):
    try:
        return float(s)
    except (TypeError, ValueError):
        return default


def runway_end(r, p, fwd):
    lat, lon = num(r[f"{p}_latitude_deg"]), num(r[f"{p}_longitude_deg"])
    if lat is None or lon is None:
        return None
    x, y = fwd(lon, lat)
    return {
        "ident": r[f"{p}_ident"], "lat": lat, "lon": lon, "x": round(x, 2), "y": round(y, 2),
        "elev_m": round(num(r[f"{p}_elevation_ft"], 0.0) * FT, 2),
        "heading_true": num(r[f"{p}_heading_degT"]),
        "displaced_m": round(num(r[f"{p}_displaced_threshold_ft"], 0.0) * FT, 1),
    }


def main():
    fwd = c.transformer()
    rwys, freqs = {}, {}
    for r in read("runways"):
        rwys.setdefault(r["airport_ident"], []).append(r)
    for f in read("airport-frequencies"):
        freqs.setdefault(f["airport_ident"], []).append(
            {"type": f["type"], "desc": f["description"], "mhz": num(f["frequency_mhz"])})

    airports = []
    for a in read("airports"):
        lat, lon = num(a["latitude_deg"]), num(a["longitude_deg"])
        if a["type"] in ("closed", "balloonport") or lat is None or not R.in_regions(lon, lat):
            continue
        x, y = fwd(lon, lat)
        runways = []
        for r in rwys.get(a["ident"], []):
            if r["closed"] == "1":
                continue
            le, he = runway_end(r, "le", fwd), runway_end(r, "he", fwd)
            runways.append({
                "length_m": round(num(r["length_ft"], 0.0) * FT, 1),
                "width_m": round(num(r["width_ft"], 0.0) * FT, 1),
                "surface": r["surface"], "lighted": r["lighted"] == "1",
                "le": le, "he": he,
            })
        airports.append({
            "ident": a["ident"], "icao": a["icao_code"] or a["gps_code"], "name": a["name"],
            "type": a["type"], "lat": lat, "lon": lon, "x": round(x, 2), "y": round(y, 2),
            "elev_m": round(num(a["elevation_ft"], 0.0) * FT, 2),
            "runways": runways, "freqs": freqs.get(a["ident"], []),
        })
        if R.region_of(lon, lat) != "mumbai_pune":
            airports[-1]["region"] = "konkan_kerala"

    navaids = []
    for n in read("navaids"):
        lat, lon = num(n["latitude_deg"]), num(n["longitude_deg"])
        if lat is None or not R.in_regions(lon, lat, NAVAID_PAD_DEG):
            continue
        x, y = fwd(lon, lat)
        navaids.append({
            "ident": n["ident"], "name": n["name"], "type": n["type"],
            "khz": num(n["frequency_khz"]), "lat": lat, "lon": lon,
            "x": round(x, 2), "y": round(y, 2),
            "elev_m": round(num(n["elevation_ft"], 0.0) * FT, 2),
            "dme_channel": n["dme_channel"], "mag_var_deg": num(n["magnetic_variation_deg"]),
            "airport": n["associated_airport"],
        })

    c.OUT.mkdir(parents=True, exist_ok=True)
    (c.OUT / "airports.json").write_text(json.dumps(airports, indent=1))
    (c.OUT / "navaids.json").write_text(json.dumps(navaids, indent=1))
    print(f"airports: {len(airports)} ({sum(len(a['runways']) for a in airports)} runways), "
          f"navaids: {len(navaids)}")


if __name__ == "__main__":
    main()
