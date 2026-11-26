"""Parser for AIP India AD 2.19 "Radio navigation and landing aids" (one eAIP aerodrome page).

The table rows give, per ILS runway end: the localizer ("LOC 28 CAT II", ident, frequency), the glide
path ("GP 28", remarks "Glide Angle 3 DEG") and the antenna coordinates (a second table, same row
order). Pure functions, no network: 29_ils_aip.py fetches the pages, tools/test_ils_real.py tests this.
"""
import html
import re

CAT = {"I": 1, "II": 2, "III": 3, "IIIA": 3, "IIIB": 3, "IIIC": 3, "1": 1, "2": 2, "3": 3}
LOC = re.compile(r"^(?:LOC|LLZ|ILS)\b\s*(\d{2}[LRC]?)\b\s*(?:CAT\s*([IV123ABC]+))?", re.I)
GP = re.compile(r"^(?:GP|GS)\b\s*(\d{2}[LRC]?)\b", re.I)
IDENT = re.compile(r"\b([A-Z]{3,4})\b")
FREQ = re.compile(r"(\d{3}\.\d{2,3})\s*MHz", re.I)
COORD = re.compile(r"(\d{2})(\d{2})(\d{2}(?:\.\d+)?)\s*([NS])\s*(\d{3})(\d{2})(\d{2}(?:\.\d+)?)\s*([EW])")
ANGLE = re.compile(r"(?:glide\s*(?:path\s*)?angle|gp\s*angle)\s*:?\s*(\d(?:\.\d+)?)\s*deg", re.I)


def _text(fragment):
    s = re.sub(r"<[^>]+>", " ", fragment)
    return re.sub(r"\s+", " ", html.unescape(s).replace("\xa0", " ")).strip()


def _rows(table):
    out = []
    for tr in re.findall(r"<tr\b[\s\S]*?</tr>", table, re.I):
        cells = [_text(td) for td in re.findall(r"<t[dh]\b[\s\S]*?</t[dh]>", tr, re.I)]
        if cells:
            out.append(cells)
    return out


def to_deg(m):
    """COORD match -> (lat, lon) in decimal degrees."""
    lat = int(m.group(1)) + int(m.group(2)) / 60.0 + float(m.group(3)) / 3600.0
    lon = int(m.group(5)) + int(m.group(6)) / 60.0 + float(m.group(7)) / 3600.0
    return (-lat if m.group(4) == "S" else lat), (-lon if m.group(8) == "W" else lon)


def _coord(text):
    m = COORD.search(text.replace(",", " "))
    if not m:
        return None
    lat, lon = to_deg(m)
    return {"lat": round(lat, 6), "lon": round(lon, 6)}


def section_tables(page):
    """The two tables of AD 2.19 (types/idents/frequencies, then coordinates/remarks) as row lists."""
    page = re.sub(r"<del\b[^>]*>[\s\S]*?</del>", "", page, flags=re.I)  # amended-out text
    i = page.find("RADIO NAVIGATION AND LANDING AIDS")
    if i < 0:
        return [], []
    j = page.find("AD 2.20", i)
    seg = page[i:j if j > 0 else len(page)]
    tables = re.findall(r"<table\b[\s\S]*?</table>", seg, re.I)
    if len(tables) < 2:
        return [], []
    a, b = _rows(tables[0]), _rows(tables[1])
    # drop the header row and the "1 2 3 4" / "5 6 7 8" column-number row
    a = [r for r in a if r[0] not in ("1", "") and not r[0].startswith("Type of aids")]
    b = [r for r in b if r[0] not in ("5", "") and not r[0].startswith("Geographical")]
    return a, b


def parse(page):
    """-> list of {runway, ident, freq_mhz, category, gs_deg, loc, gp} (loc / gp: {lat, lon} or None)."""
    a, b = section_tables(page)
    aligned = len(a) == len(b)
    recs = {}
    for k, row in enumerate(a):
        kind = row[0]
        coord = _coord(b[k][0]) if aligned and b[k] else None
        remark = b[k][-1] if aligned and b[k] else ""
        m = LOC.match(kind)
        if m and "DME" not in kind.upper():
            rwy = m.group(1).upper()
            ident = IDENT.search(row[1]) if len(row) > 1 else None
            f = FREQ.search(row[2]) if len(row) > 2 else None
            if not ident or not f:
                continue
            recs[rwy] = {"runway": rwy, "ident": ident.group(1), "freq_mhz": float(f.group(1)),
                         "category": CAT.get((m.group(2) or "").upper()), "gs_deg": None, "loc": coord, "gp": None}
            continue
        g = GP.match(kind)
        if g and g.group(1).upper() in recs:
            r = recs[g.group(1).upper()]
            r["gp"] = coord
            ang = ANGLE.search(remark)
            if ang:
                r["gs_deg"] = float(ang.group(1))
    return sorted(recs.values(), key=lambda r: r["runway"])
