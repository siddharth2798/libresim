"""Parsers for AIP India SIDs and STARs (text from `pdftotext -layout`). Pure functions, no network or files:
31_procedures.py fetches the PDFs, tools/test_procedures.py tests this.

Two published forms:
  RNAV  "TABULAR DESCRIPTION" tables (AIP Supplement 121/2026 for Mumbai): one table per procedure, titled
        "SID PPN3A - RWY 27" or "STAR OPAKA 3K RWY 27", one row per leg: serial, path terminator, waypoint, fly-over,
        course, distance, turn, altitude ("+6000" at or above, "-FL120" at or below, "@FL280" at; a second line under it
        makes a window), speed limit ("-250.00", "@190.00"), VPA, navigation specification. A holding (HM) or a vector
        leg (VM) ends the procedure. The waypoint list ("BB104  N 19:05:21.34 E 073:00:55.26") gives the coordinates.
  Conventional  the ROUTING table of a SID chart (Pune AD 2.24): "OPAKA 2A  28  Climb on runway Hdg to D 5.0 PPN at or
        above 2900', Climbing turn right Hdg 077° to intercept R030." Only what the row states is kept: the DME fix on
        the runway heading with its altitude, then the named end fix.
Legs without a fix (VA heading to an altitude, VM vectors) are not kept: the GPS flies fix to fix.
"""
import re

TITLE = re.compile(r"^\s*(SID|STAR)\s+([A-Z]{2,5})\s?(\d[A-Z])\s*-?\s*RWY\s*(\d{2}[LRC]?)\b")
ROW = re.compile(r"^\s*(\d{2,3})\s+([A-Z]{2})\b(.*)$")
COURSE = re.compile(r"\d{1,3}\.\d{1,2}°?\s*\(\s*(\d{1,3}\.\d{1,2})°?\s*\)")
NAV_SPEC = re.compile(r"RNAV\s*\d|RNP\s*[\d.]+")
LIMIT = re.compile(r"^([+@-])(FL)?(\d{2,5})(?:\.\d+)?$")
FIX = re.compile(r"^[A-Z][A-Z0-9]{1,4}$")
WPT = re.compile(r"\b([A-Z][A-Z0-9]{1,4})\s+N\s*(\d{1,2}):(\d{2}):(\d{2}(?:\.\d+)?)\s+E\s*(\d{1,3}):(\d{2}):(\d{2}(?:\.\d+)?)")
END_LEGS = ("HM", "HA", "HF", "VM", "FM")
SPEED_MAX_KT = 400  # a +/-/@ number below this is a speed limit, above it an altitude in feet

CONV_ROW = re.compile(r"^\s*([A-Z]{5})\s?(\d[A-Z])\s+(\d{2}[LRC]?)\s+(Climb\b.*)$", re.I)
CONV_DME = re.compile(r"to\s+D\s*([\d.]+)\s*([A-Z]{3})\s+at\s+or\s+above\s+(\d{3,5})\s*['’]", re.I)


def _limit(tok):
    """'+FL110' -> ('alt', '+', 11000); '-250.00' -> ('spd', '-', 250); None when not a limit."""
    m = LIMIT.match(tok)
    if not m:
        return None
    v = int(m.group(3)) * (100 if m.group(2) else 1)
    if not m.group(2) and v < SPEED_MAX_KT:
        return "spd", m.group(1), v
    return "alt", m.group(1), v


def _apply(leg, kind, sign, v):
    lo, hi = ("lo_ft", "hi_ft") if kind == "alt" else ("spd_lo_kt", "spd_kt")
    if sign in "+@":
        leg[lo] = v
    if sign in "-@":
        leg[hi] = v


def _row(rest):
    """Tokens of a leg row after the path terminator -> (fix or '', fly-over, limits [(kind, sign, value)])."""
    rest = NAV_SPEC.sub(" ", COURSE.sub(" ", rest))
    fix, over, limits = "", False, []
    for tok in rest.split():
        lim = _limit(tok)
        if lim:
            limits.append(lim)
        elif tok == "Y" and not over:
            over = True
        elif not fix and not limits and FIX.match(tok) and tok not in ("L", "R", "Y", "N"):
            fix = tok
    return fix, over, limits


def parse_tables(text):
    """Every TABULAR DESCRIPTION procedure in `text`: [{kind, name, rwy, legs: [{fix, lo_ft, hi_ft, spd_kt, ...}],
    vectors_true (when it ends in a VM leg)}].
    A fix-less leg's limits are dropped with it; a window's second line (only a limit) joins the row above."""
    procs, cur, leg, done = [], None, None, False
    for line in text.splitlines():
        t = TITLE.match(line)
        if t:
            cur = {"kind": t.group(1), "name": t.group(2) + t.group(3), "rwy": t.group(4), "legs": []}
            procs.append(cur)
            leg, done = None, False
            continue
        if cur is None or done:
            continue
        r = ROW.match(line)
        if r:
            if r.group(2) in END_LEGS:
                done = True  # the published path ends here (vectors or the holding)
                crs = COURSE.search(r.group(3))
                if r.group(2) == "VM" and crs:
                    cur["vectors_true"] = float(crs.group(1))  # ATC vectors from the last fix, on this true heading
                continue
            fix, over, limits = _row(r.group(3))
            leg = {"fix": fix, "path": r.group(2)}
            if over:
                leg["fly_over"] = True
            for lim in limits:
                _apply(leg, *lim)
            cur["legs"].append(leg)
            continue
        toks = line.split()
        if leg is not None and toks and all(_limit(x) for x in toks):
            for x in toks:
                _apply(leg, *_limit(x))
    for p in procs:
        p["legs"] = [{k: v for k, v in g.items() if k != "path"} for g in p["legs"] if g["fix"]]
    return [p for p in procs if p["legs"]]


def parse_waypoints(text):
    """{ident: (lat, lon)} from a waypoint list."""
    out = {}
    for m in WPT.finditer(text):
        lat = int(m.group(2)) + int(m.group(3)) / 60.0 + float(m.group(4)) / 3600.0
        lon = int(m.group(5)) + int(m.group(6)) / 60.0 + float(m.group(7)) / 3600.0
        out[m.group(1)] = (round(lat, 7), round(lon, 7))
    return out


def parse_conventional(text):
    """ROUTING rows of a conventional SID chart: [{kind: SID, name, rwy, end, dme: (nm, vor, alt_ft) or None}]."""
    out = []
    for line in text.splitlines():
        m = CONV_ROW.match(line)
        if not m:
            continue
        d = CONV_DME.search(m.group(4))
        out.append({"kind": "SID", "name": m.group(1).upper() + m.group(2).upper(), "rwy": m.group(3), "end": m.group(1).upper(),
                    "dme": (float(d.group(1)), d.group(2).upper(), int(d.group(3))) if d else None})
    return out


def dme_ident(radial_mag, dist_nm):
    """ARINC 424 name of a DME fix: D + radial (3 digits) + distance letter (A = 1 nm ... E = 5 nm), e.g. D271E."""
    n = int(round(dist_nm))
    return "D%03d%s" % (int(round(radial_mag)) % 360 or 360, chr(64 + n) if 1 <= n <= 26 else "Z")


def ray_circle(p, hdg_true_deg, c, r):
    """First point at distance r from c along the ray from p (x east, y north) on the true heading; None if it misses."""
    import math
    dx, dy = math.sin(math.radians(hdg_true_deg)), math.cos(math.radians(hdg_true_deg))
    fx, fy = p[0] - c[0], p[1] - c[1]
    b = fx * dx + fy * dy
    disc = b * b - (fx * fx + fy * fy - r * r)
    if disc < 0.0:
        return None
    t = -b + math.sqrt(disc)  # the far root: the aircraft starts inside the circle or before it
    if t < 0.0:
        return None
    return p[0] + dx * t, p[1] + dy * t
