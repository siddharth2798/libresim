"""Published SIDs and STARs -> data/processed/procedures.json (gitignored), for the Route step, the MCDU and the FMS.

Sources (Airports Authority of India, the eAIP archive steps 28 and 29 read):
  - AIRAC AIP Supplements with RNAV-1 SIDs and STARs and their TABULAR DESCRIPTION (SUPS below; Mumbai's are not in its
    AD 2.24 chart list). Every leg keeps its fix, altitude limits (lo_ft at or above, hi_ft at or below, both = at) and
    speed limit (spd_kt at or below).
  - The SID charts of each airport's AD 2.24 list (`<ICAO>-SID-RWY-NN.pdf`): conventional SIDs (Pune), whose ROUTING table
    gives a DME fix on the runway heading with an at-or-above altitude, then the end fix.
Pune (VAPO) publishes no STAR (arrivals are radar vectored); the game keeps its own arrival fixes there.
Fix coordinates: the supplement's waypoint list, else airways.json (step 28), else navaids.json (step 05).
Text comes from `pdftotext -layout` (poppler: brew install poppler, apt install poppler-utils). Without it, or offline with
nothing cached, the old procedures.json stays. PDFs are cached in data/raw/aai/<cycle>/ and never shipped.
For simulation only, not navigation.
"""
import json
import math
import re
import shutil
import subprocess
import sys
from datetime import date

import aai_eaip as aai
import common as c
import procedures_aip as pa

SUPS = {  # airport -> (supplement PDF under <cycle>/pdf/SUPs/, effective date)
    "VABB": ("SUP2026/AIPS_2026_121.pdf", "2026-08-06"),
    "VANM": ("SUP2026/AIPS_2026_122.pdf", "2026-08-06"),
}
SUP_URL = "https://aim-india.aai.aero.in/eAIP_Archive/{cycle}/pdf/SUPs/{name}"
CHART_LINK = re.compile(r"href='([A-Z]{4}-(?:SID|STAR)[^']*\.pdf)'", re.I)
NM = 1852.0


def text_of(pdf_bytes):
    """Pages of a PDF as layout text (pdftotext reads stdin as '-')."""
    r = subprocess.run(["pdftotext", "-layout", "-", "-"], input=pdf_bytes, capture_output=True, timeout=300)
    return r.stdout.decode("utf-8", "replace").split("\f")


def sup_pdf(cycle, name):
    path = c.RAW / "aai" / cycle / "sup" / name.replace("/", "_")
    if path.exists() and path.stat().st_size > 10000:
        return path.read_bytes()
    data = aai.fetch(SUP_URL.format(cycle=cycle, name=name))
    if not data.startswith(b"%PDF"):
        raise RuntimeError("not a PDF")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


def runway_end(airports, icao, rwy):
    for a in airports:
        if a.get("icao") != icao:
            continue
        for r in a.get("runways", []):
            for side in ("le", "he"):
                e = r.get(side)
                if isinstance(e, dict) and str(e.get("ident", "")).zfill(2) == rwy:
                    return e
    return None


def conventional(icao, rows, airports, navaids, aw_fixes, points):
    """Conventional SID rows -> procedures; adds the DME fixes to `points` (ident -> (x, y)). The VOR is the navaids.json
    station, else the airways fix of that name (OurAirports lacks some, e.g. PPN)."""
    out = []
    for r in rows:
        end = runway_end(airports, icao, r["rwy"])
        legs = []
        if r["dme"] and end:
            nm, vor, alt = r["dme"]
            v = next((n for n in navaids if n.get("ident") == vor and str(n.get("type", "")).startswith("VOR")), None) \
                or aw_fixes.get(vor)
            if v:
                hit = pa.ray_circle((end["x"], end["y"]), float(end["heading_true"]), (v["x"], v["y"]), nm * NM)
                if hit:
                    var = v.get("mag_var_deg") if v.get("mag_var_deg") is not None else -0.3
                    radial = math.degrees(math.atan2(hit[0] - v["x"], hit[1] - v["y"])) - var
                    ident = pa.dme_ident(radial % 360.0, nm)
                    points[ident] = hit
                    legs.append({"fix": ident, "lo_ft": alt})
        legs.append({"fix": r["end"]})
        out.append({"kind": "SID", "name": r["name"], "rwy": r["rwy"], "legs": legs, "form": "conventional"})
    return out


def wanted(airports):
    return sorted({a["icao"] for a in airports if a.get("icao") and len(a["icao"]) == 4 and a.get("runways")
                   and a.get("type") != "heliport"})


def main():
    out = c.OUT / "procedures.json"
    if shutil.which("pdftotext") is None:
        print("procedures: pdftotext (poppler) not found; keeping " + ("the old file" if out.exists() else "nothing"))
        return 0
    try:
        cycle, menu = aai.latest_cycle(b"IN-AD 2.1")
    except BaseException as e:  # noqa: BLE001 - SystemExit when nothing is reachable and nothing cached
        print(f"procedures: no eAIP archive reachable ({e}); keeping {'the old file' if out.exists() else 'nothing'}")
        return 0
    airports = json.loads((c.OUT / "airports.json").read_text())
    navaids = json.loads((c.OUT / "navaids.json").read_text())
    aw = c.OUT / "airways.json"
    aw_fixes = json.loads(aw.read_text()).get("fixes", {}) if aw.exists() else {}
    fwd = c.transformer()
    latlon, points, result, sources = {}, {}, {}, []
    for icao, (name, eff) in SUPS.items():
        if icao not in wanted(airports):
            continue
        try:
            pages = text_of(sup_pdf(cycle, name))
        except Exception as e:  # noqa: BLE001 - one source failing must not stop the rest
            print(f"procedures: {icao} supplement {name}: {e}")
            continue
        procs = []
        for page in pages:
            if "Descriptor" in page:
                procs += pa.parse_tables(page)
            latlon.update(pa.parse_waypoints(page))
        result.setdefault(icao, []).extend(dict(p, form="rnav") for p in procs)
        sources.append(f"AIP SUP {name.rsplit('_', 2)[-2]}/{name.rsplit('_', 2)[-1][:-4]} ({icao}, effective {eff})")
    have = set(re.findall(r"IN-AD 2\.1([A-Z0-9]{4})-en-GB\.html", menu))
    for icao in wanted(airports):
        if icao not in have or icao in SUPS:
            continue
        try:
            charts = CHART_LINK.findall(aai.cached(cycle, f"AD 2.1{icao}_BChart.html").decode("utf-8", "replace"))
        except Exception as e:  # noqa: BLE001
            print(f"procedures: {icao} chart list: {e}")
            continue
        for ch in charts:
            if "-SID-" not in ch.upper():
                continue  # no conventional STAR form is parsed (none is published in the region)
            try:
                txt = "\n".join(text_of(aai.cached(cycle, ch)))
            except Exception as e:  # noqa: BLE001
                print(f"procedures: {icao} {ch}: {e}")
                continue
            rows = pa.parse_conventional(txt)
            if rows:
                result.setdefault(icao, []).extend(conventional(icao, rows, airports, navaids, aw_fixes, points))
            if rows:
                sources.append(f"AD 2.24 {ch}")
    fixes = {}
    for ident, (lat, lon) in latlon.items():
        x, y = fwd(lon, lat)
        fixes[ident] = {"x": round(x, 1), "y": round(y, 1)}
    for ident, (x, y) in points.items():
        fixes[ident] = {"x": round(x, 1), "y": round(y, 1)}
    vor_pos = {n["ident"]: n for n in navaids}
    doc_airports, missing = {}, set()
    for icao, procs in result.items():
        for p in procs:
            for g in p["legs"]:
                f = g["fix"]
                if f not in fixes:
                    src = aw_fixes.get(f) or vor_pos.get(f)
                    if src:
                        fixes[f] = {"x": round(float(src["x"]), 1), "y": round(float(src["y"]), 1)}
                    else:
                        missing.add(f)
        ok = [p for p in procs if all(g["fix"] in fixes for g in p["legs"])]
        if not ok:
            continue
        doc_airports[icao] = {"sids": [p for p in ok if p["kind"] == "SID"], "stars": [p for p in ok if p["kind"] == "STAR"]}
        for p in ok:
            p.pop("kind")
    if not doc_airports:
        print("procedures: nothing parsed; keeping the old file")
        return 0
    out.write_text(json.dumps({"source": "AIP India (AAI): " + "; ".join(sources), "cycle": cycle, "fetched": date.today().isoformat(),
                               "note": "For simulation only, not navigation.", "airports": doc_airports,
                               "fixes": {k: fixes[k] for k in sorted(fixes)}}, indent=1))
    for icao, d in sorted(doc_airports.items()):
        print(f"{icao}: {len(d['sids'])} SIDs, {len(d['stars'])} STARs")
    if missing:
        print("procedures: no position for " + ", ".join(sorted(missing)) + " (their procedures are left out)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
