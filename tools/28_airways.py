"""AAI eAIP ENR 3.1 / 3.2 -> data/processed/airways.json (gitignored).

The Airports Authority of India publishes each ATS route as one HTML page in the
public eAIP archive. This keeps the designator, the significant points in order
and their coordinates, for routes that cross the sim regions. The HTML is cached
under data/raw/aai and is not shipped. Not for navigation.
"""
import html
import json
import re
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, timedelta

import common as c
from shapely.geometry import LineString, box

HOST = "https://aim-india.aai.aero.in/eAIP_Archive/{cycle}/eAIP/{name}"
UA = "libresim-airways/1.0 (flight simulator; not for navigation)"
PAD = 1.0
SKIP = {"DVOR", "DME", "VOR", "NDB", "TACAN", "VORTAC", "RNAV", "GNSS",
       "FIR", "ACC", "APP", "TWR", "MEA", "MOCA", "COP", "CLASS", "ODD", "EVEN", "FL"}
COORD = re.compile(r"(\d{6,7}(?:\.\d+)?)([NS])\s+(\d{6,8}(?:\.\d+)?)([EW])")
PAGE = re.compile(r"IN-ENR 3\.[12]([A-Z][A-Z0-9]*)-en-GB\.html")
DEL = re.compile(r"<del\b[^>]*>[\s\S]*?</del>", re.I)


def airac_dates():
    d, end = date(2025, 1, 23), date.today() + timedelta(days=40)
    out = []
    while d <= end:
        out.append(d.strftime("%d-%m-%Y"))
        d += timedelta(days=28)
    return out


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    last = None
    for n in range(3):
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 - retry any transport or HTTP error
            last = e
            time.sleep(0.4 * (n + 1))
    raise last


def cached(cycle, name):
    path = c.RAW / "aai" / cycle / name.replace(" ", "_")
    if path.exists() and path.stat().st_size > 800:
        data = path.read_bytes()
        if not data.lstrip().lower().startswith(b"<!doctype html>"):
            return data
    data = fetch(HOST.format(cycle=cycle, name=urllib.parse.quote(name)))
    if data.lstrip().lower().startswith(b"<!doctype html>"):
        raise RuntimeError("not an eAIP page")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


def latest_cycle():
    for cycle in reversed(airac_dates()):
        try:
            body = cached(cycle, "Menu-en-GB.html")
        except Exception:
            continue
        if b"IN-ENR 3.1" in body and b"CONVENTIONAL NAVIGATION" in body:
            return cycle, body.decode("utf-8", "replace")
    raise SystemExit("no AAI eAIP archive with ENR 3.1 route pages")


def dms(num, hem):
    whole, _, frac = num.partition(".")
    n = 2 if hem in "NS" else len(whole) - 4
    if n < 1 or len(whole) < n + 4:
        return None
    deg, mn = int(whole[:n]), int(whole[n:n + 2])
    sec = float(whole[n + 2:] + (("." + frac) if frac else ""))
    if mn >= 60 or sec >= 60.0:
        return None
    v = deg + mn / 60.0 + sec / 3600.0
    return -v if hem in "SW" else v


def plain(fragment):
    text = re.sub(r"<[^>]+>", " ", fragment)
    text = html.unescape(text).replace("\xa0", " ")
    return re.sub(r"\s+", " ", text).strip()


def point_of(cell):
    text = plain(cell)
    m = COORD.search(text)
    if not m:
        return None
    lat, lon = dms(m.group(1), m.group(2)), dms(m.group(3), m.group(4))
    head = text[:m.start()]
    # "ANGAL(VABF/OYSC FIR)" is the fix; "DVOR/DME (MMV)" keeps the ident in parentheses.
    lead = re.match(r"^([A-Z][A-Z0-9]{1,4})\s*\(", head)
    parens = re.findall(r"\(([A-Z0-9]{2,5})\)", head)
    if lead and lead.group(1) not in SKIP:
        ident = lead.group(1)
    elif parens:
        ident = parens[-1]
    else:
        words = [w for w in re.findall(r"\b([A-Z][A-Z0-9]{1,4})\b", head) if w not in SKIP]
        ident = words[-1] if words else None
    if ident is None or lat is None or lon is None:
        return None
    return ident, lat, lon


def direction_of(page, fixes):
    text = plain(page)
    remarks = text[text.rfind("REMARKS"):].upper() if "REMARKS" in text else ""
    card = None
    for name in ("EAST", "WEST", "NORTH", "SOUTH"):
        if f"{name}BOUND ONLY" in remarks:
            card = name
    if card is None and re.search(r"\bONE[- ]?WAY\b|UNIDIRECTIONAL", remarks):
        down, up = page.count("&#8595;"), page.count("&#8593;")
        if down and not up:
            return "forward"
        if up and not down:
            return "back"
        return "both"
    if card is None or len(fixes) < 2:
        return "both"
    dlon = fixes[-1][2] - fixes[0][2]
    dlat = fixes[-1][1] - fixes[0][1]
    along = {"EAST": dlon >= 0, "WEST": dlon <= 0, "NORTH": dlat >= 0, "SOUTH": dlat <= 0}[card]
    return "forward" if along else "back"


def parse_page(raw):
    page = DEL.sub(" ", raw.decode("utf-8", "replace"))
    fixes = []
    for row in re.findall(r"<tr\b[^>]*>([\s\S]*?)</tr>", page, re.I):
        cells = re.findall(r"<td\b[^>]*>([\s\S]*?)</td>", row, re.I)
        if len(cells) < 2:
            continue
        pt = point_of(cells[1])
        if pt is None or (fixes and fixes[-1][0] == pt[0]):
            continue
        fixes.append(pt)
    return fixes, direction_of(page, fixes)


def download_all(cycle, names):
    out = {}

    def one(name):
        try:
            return name, cached(cycle, name)
        except Exception as e:  # noqa: BLE001
            return name, e

    with ThreadPoolExecutor(max_workers=6) as pool:
        for fut in as_completed([pool.submit(one, n) for n in names]):
            name, data = fut.result()
            out[name] = data
            if len(out) % 100 == 0:
                print(f"  fetched {len(out)}/{len(names)}")
    return out


def crosses(fixes, region):
    line = LineString([(lon, lat) for _, lat, lon in fixes])
    return region.intersects(line)


def main():
    cycle, menu = latest_cycle()
    names = sorted(set(re.findall(r"IN-ENR 3\.[12][A-Z][A-Z0-9]*-en-GB\.html", menu)))
    print(f"cycle {cycle}: {len(names)} route pages")
    pages = download_all(cycle, names)
    bb = c.BBOX
    region = box(bb[0] - PAD, bb[1] - PAD, bb[2] + PAD, bb[3] + PAD).union(c.corridor_lonlat().buffer(PAD))
    fwd = c.transformer()
    airways, fixes, empty, oneway = {}, {}, [], 0
    for name in names:
        raw = pages[name]
        if isinstance(raw, Exception):
            empty.append(name + " FETCH")
            continue
        pts, direction = parse_page(raw)
        if len(pts) < 2:
            chart = name.replace("-en-GB.html", "_TChart.html")
            try:
                pts, direction = parse_page(cached(cycle, chart))
            except Exception:
                pass
        if len(pts) < 2 or not crosses(pts, region):
            if len(pts) < 2:
                empty.append(name)
            continue
        ident = PAGE.search(name).group(1)
        if ident in airways:
            print(f"duplicate {ident}; keeping the longer list")
            if len(pts) <= len(airways[ident]["fixes"]):
                continue
        airways[ident] = {"fixes": [p[0] for p in pts], "direction": direction}
        if direction != "both":
            oneway += 1
        for pid, lat, lon in pts:
            if pid in fixes and (abs(fixes[pid]["lat"] - lat) > 0.02 or abs(fixes[pid]["lon"] - lon) > 0.02):
                print(f"fix {pid} disagrees ({lat:.4f},{lon:.4f}) vs stored")
                continue
            x, y = fwd(lon, lat)
            fixes[pid] = {"lat": round(lat, 6), "lon": round(lon, 6), "x": round(x, 1), "y": round(y, 1)}
    doc = {
        "source": "Airports Authority of India eAIP ENR 3.1 and ENR 3.2",
        "cycle": cycle,
        "url": f"https://aim-india.aai.aero.in/eAIP_Archive/{cycle}/eAIP/",
        "fetched": date.today().isoformat(),
        "note": "Route designators, point order and coordinates for simulation. Not for navigation.",
        "airways": {k: airways[k] for k in sorted(airways)},
        "fixes": {k: fixes[k] for k in sorted(fixes)},
    }
    c.OUT.mkdir(parents=True, exist_ok=True)
    (c.OUT / "airways.json").write_text(json.dumps(doc, indent=1))
    print(f"kept {len(airways)} airways, {len(fixes)} fixes, {oneway} one-way, "
          f"{len(empty)} pages without a track")
    if empty[:8]:
        print("  empty:", ", ".join(empty[:8]))
    sample = next((k for k, a in airways.items() if "BBB" in a["fixes"]), "")
    if sample:
        print(f"  sample {sample}: {' '.join(airways[sample]['fixes'][:8])}")


if __name__ == "__main__":
    main()
