"""Real ILS records (tools/29_ils_aip.py + tools/ils_overrides.json) matched to the sim's runway ends.

match() keys a record by (airport ICAO, runway end ident) and checks it against the runway geometry:
the bearing from the threshold to the real localizer antenna (beyond the far end) must agree with the runway's true
heading. Pure functions (no GDAL): the caller gives the projection `fwd(lon, lat) -> (x, y)`.
"""
import json
import math

TOL_DEG = 5.0       # beyond this the antenna position is not trusted (logged "mismatch", coordinates dropped)
REJECT_DEG = 25.0   # beyond this the record is for another runway (logged "rejected", not used)
NM = 1852.0
SEP_NM = 150.0      # a simulated ILS never shares a frequency with a real one closer than this


def bearing(ax, ay, bx, by):
    return math.degrees(math.atan2(bx - ax, by - ay)) % 360.0


def angle_diff(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def load_overrides(path):
    """tools/ils_overrides.json: {"entries": [{airport, runway, ident, freq_mhz, category, gs_deg, source}]}; an
    entry with "remove": true deletes the AIP record of that end."""
    try:
        return json.loads(path.read_text()).get("entries", [])
    except (OSError, ValueError):
        return []


def records(aip, overrides):
    """-> ({(airport, runway): record}, set of airports whose AIP page was read)."""
    recs, pages = {}, set()
    if aip:
        pages = set(aip.get("pages", []))
        for r in aip.get("records", []):
            recs[(r["airport"], r["runway"])] = dict(r, source="AIP India AIRAC " + str(aip.get("cycle", "")))
    for o in overrides:
        key = (o["airport"], str(o["runway"]))
        if o.get("remove"):
            recs.pop(key, None)
        else:
            recs[key] = dict(o, source=o.get("source", "ils_overrides.json"))
        pages.add(o["airport"])
    return recs, pages


def match(runways, recs, fwd):
    """-> (real: {(airport, runway end): record with "course_ok"}, log lines). Every record is accounted for."""
    real, log, used = {}, [], set()
    for r in runways:
        for i in (0, 1):
            thr, far = r["ends"][i], r["ends"][1 - i]
            key = (r["airport"], thr["ident"])
            rec = recs.get(key)
            if rec is None:
                continue
            used.add(key)
            rec = dict(rec, course_ok=True)
            hdg = bearing(thr["x"], thr["y"], far["x"], far["y"])
            loc = rec.get("loc")
            if loc:
                lx, ly = fwd(loc["lon"], loc["lat"])
                d = angle_diff(bearing(thr["x"], thr["y"], lx, ly), hdg)
                if d > REJECT_DEG:
                    log.append(f'rejected {key[0]} {key[1]} {rec["ident"]}: localizer antenna lies {d:.0f} deg off the runway')
                    continue
                if d > TOL_DEG:
                    rec["course_ok"] = False
                    log.append(f'mismatch {key[0]} {key[1]} {rec["ident"]}: localizer antenna lies {d:.1f} deg off the runway (coordinates ignored)')
            real[key] = rec
    for key, rec in recs.items():
        if key not in used:
            log.append(f'unmatched {key[0]} {key[1]} {rec["ident"]}: no such runway end in the sim')
    return real, log


def blocked_freqs(real, airports, airport):
    """Frequencies of REAL ILS within SEP_NM of `airport` (airports: ICAO -> (x, y) metres)."""
    ax, ay = airports.get(airport, (0.0, 0.0))
    out = set()
    for (icao, _), rec in real.items():
        px, py = airports.get(icao, (ax, ay))
        if math.hypot(px - ax, py - ay) <= SEP_NM * NM:
            out.add(round(rec["freq_mhz"], 2))
    return out
