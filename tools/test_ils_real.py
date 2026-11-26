"""Self-check for the real-ILS pipeline (tools/ils_aip.py parser, ils_real.py matcher, 14_ils.py build).
Plain asserts, also collected by pytest if installed. Run: python3 tools/test_ils_real.py
No data/ files and no GDAL needed: a flat fake projection (1 deg = 100 km) stands in for the world one."""
import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import ils_aip  # noqa: E402
import ils_real  # noqa: E402

ils14 = importlib.import_module("14_ils")

DEG = 100000.0


def fwd(lon, lat):
    return lon * DEG, lat * DEG


def runway(icao, a, b, x0, y0, length=3000.0):
    """East-west runway: end a (ident a) at x0, end b (ident b) length metres east."""
    return {"airport": icao, "width": 45.0, "length": length, "surface": "asphalt", "ends": [
        {"ident": a, "x": x0, "y": y0, "h": 10.0}, {"ident": b, "x": x0 + length, "y": y0, "h": 10.0}]}


def rec(icao, rwy, ident, freq, cat=1, lon=None, lat=None, gs=None):
    r = {"airport": icao, "runway": rwy, "ident": ident, "freq_mhz": freq, "category": cat, "gs_deg": gs,
         "loc": None, "gp": None}
    if lon is not None:
        r["loc"] = {"lon": lon, "lat": lat}
    return r


def build(rws, recs, pages=(), airports=None):
    r, p = ils_real.records({"cycle": "t", "pages": list(pages), "records": recs}, [])
    ap = airports or {w["airport"]: (w["ends"][0]["x"], w["ends"][0]["y"]) for w in rws}
    return ils14.build(rws, ap, set(), r, p, fwd)


def test_real_replaces_simulated():
    rw = [runway("VAAA", "09", "27", 0.0, 0.0)]
    out, _ = build(rw, [rec("VAAA", "09", "IABC", 109.9, 2, gs=3.2)], ["VAAA"])
    assert len(out) == 1, "one-ended: the opposite end gets no invented ILS"
    o = out[0]
    assert o["runway"] == "09" and o["ident"] == "IABC" and o["freq_mhz"] == 109.9
    assert o["simulated"] is False and o["category"] == 2 and o["gs_deg"] == 3.2
    assert abs(o["course_true"] - 90.0) < 0.1 and o["loc"]["x"] == 3300.0  # standard siting kept


def test_simulated_fallback_unchanged():
    out, _ = build([runway("VAAA", "09", "27", 0.0, 0.0)], [])
    assert [(o["runway"], o["ident"], o["simulated"]) for o in out] == [("09", "IAA09", True), ("27", "IAA27", True)]
    assert all("category" not in o and o["gs_deg"] == 3.0 for o in out)
    assert out[0]["freq_mhz"] == 108.1 and out[1]["freq_mhz"] == 108.3


def test_short_or_non_indian_runway_stays_without_ils_but_real_one_is_kept():
    rw = [runway("VAAA", "09", "27", 0.0, 0.0, 1500.0)]
    assert build(rw, [])[0] == []
    out, _ = build(rw, [rec("VAAA", "27", "ISHT", 110.5)], ["VAAA"])
    assert [o["runway"] for o in out] == ["27"], "a real ILS needs no minimum length"


def test_page_without_ils_keeps_simulated():
    out, _ = build([runway("VAAA", "09", "27", 0.0, 0.0)], [], ["VAAA"])
    assert len(out) == 2 and all(o["simulated"] for o in out)


def test_frequency_not_shared_with_real_ils_nearby():
    rw = [runway("VAAA", "09", "27", 0.0, 0.0), runway("VAAB", "09", "27", 50000.0, 0.0)]
    # VAAB's real ILS uses 108.10, the first simulated channel of VAAA (50 km away)
    out, _ = build(rw, [rec("VAAB", "09", "IBBB", 108.1)], ["VAAB"])
    sim = [o for o in out if o["simulated"]]
    assert sim and all(o["freq_mhz"] != 108.1 for o in sim), [o["freq_mhz"] for o in sim]
    # ... but 300 nm away the same channel is fine
    far = {"VAAA": (0.0, 0.0), "VAAB": (300.0 * 1852.0, 0.0)}
    out, _ = build(rw, [rec("VAAB", "09", "IBBB", 108.1)], ["VAAB"], far)
    assert any(o["simulated"] and o["freq_mhz"] == 108.1 for o in out)


def test_course_check():
    rw = [runway("VAAA", "09", "27", 0.0, 0.0)]
    # localizer 3300 m east of the threshold on the centreline: fine
    ok, log = build(rw, [rec("VAAA", "09", "IOK", 109.1, lon=0.033, lat=0.0)], ["VAAA"])
    assert len(ok) == 1 and log == []
    # 10 degrees off: kept, logged as a mismatch
    mm, log = build(rw, [rec("VAAA", "09", "IMM", 109.1, lon=0.033, lat=0.0058)], ["VAAA"])
    assert len(mm) == 1 and log and log[0].startswith("mismatch")
    # on the wrong side (180 degrees): rejected, the runway then gets no record
    bad, log = build(rw, [rec("VAAA", "09", "IBAD", 109.1, lon=-0.03, lat=0.0)], ["VAAA"])
    assert log and log[0].startswith("rejected") and not [o for o in bad if not o["simulated"]]
    # a record for a runway that does not exist is logged
    _, log = build(rw, [rec("VAAA", "18", "INO", 109.1)], ["VAAA"])
    assert log and log[0].startswith("unmatched")


def test_overrides():
    rw = [runway("VAAA", "09", "27", 0.0, 0.0)]
    base = {"cycle": "t", "pages": ["VAAA"], "records": [rec("VAAA", "09", "IOLD", 109.1)]}
    r, _ = ils_real.records(base, [{"airport": "VAAA", "runway": "09", "ident": "INEW", "freq_mhz": 110.5, "category": 3}])
    assert ils14.build(rw, {"VAAA": (0, 0)}, set(), r, {"VAAA"}, fwd)[0][0]["ident"] == "INEW"
    r, _ = ils_real.records(base, [{"airport": "VAAA", "runway": "09", "remove": True}])
    assert "VAAA" not in {a for a, _ in r}


def test_schema_stays_compatible():
    """Everything an older reader (nav_database.gd, runway lights, map) reads is still there, simulated or real."""
    need = {"airport", "runway", "ident", "freq_mhz", "course_true", "loc", "gs", "threshold", "gs_deg", "simulated"}
    out, _ = build([runway("VAAA", "09", "27", 0.0, 0.0), runway("VAAB", "09", "27", 50000.0, 0.0)],
                   [rec("VAAB", "09", "IBBB", 110.7, 3)], ["VAAB"])
    assert len(out) == 3 and all(need <= set(o) for o in out)


PAGE = """<p>RADIO NAVIGATION AND LANDING AIDS</p>
<table><tr><th>Type of aids</th><th>Identification</th><th>Frequency</th><th>Hours</th></tr>
<tr><td>1</td><td>2</td><td>3</td><td>4</td></tr>
<tr><td><p>LOC 26 </p><p> CAT II</p></td><td>IBGM</td><td>111.300 MHz</td><td>HO</td></tr>
<tr><td>GP 26</td><td>&nbsp;</td><td>332.300 MHz</td><td>HO</td></tr>
<tr><td>DME ILS 26</td><td>IBGM</td><td>CH50X</td><td>HO</td></tr>
<tr><td>LOC 08R</td><td>IXYZ</td><td>109.500 MHz</td><td>H24</td></tr>
<tr><td>NDB</td><td>SI</td><td>475 kHz</td><td>HO</td></tr></table>
<table><tr><td>Geographical coordinates</td><td>Elev</td><td>Radius</td><td>Remarks</td></tr>
<tr><td>5</td><td>6</td><td>7</td><td>8</td></tr>
<tr><td>155123.0N 0743609.8E</td><td></td><td></td><td></td></tr>
<tr><td>155133.3N 0743728.2E</td><td></td><td></td><td>Glide Angle 3.5 Deg</td></tr>
<tr><td>155133.2N 0743728.3E</td><td>2481 FT</td><td></td><td></td></tr>
<tr><td>155100.0N 0743600.0E</td><td></td><td></td><td></td></tr>
<tr><td>155000.0N 0743000.0E</td><td></td><td></td><td></td></tr></table>
<p>AD 2.20 LOCAL TRAFFIC REGULATIONS</p>"""


def test_parse_ad219():
    got = ils_aip.parse(PAGE)
    assert [g["runway"] for g in got] == ["08R", "26"]
    g = got[1]
    assert (g["ident"], g["freq_mhz"], g["category"], g["gs_deg"]) == ("IBGM", 111.3, 2, 3.5)
    assert abs(g["loc"]["lat"] - (15 + 51 / 60 + 23 / 3600)) < 1e-6 and abs(g["loc"]["lon"] - (74 + 36 / 60 + 9.8 / 3600)) < 1e-6
    assert got[0]["category"] is None and got[0]["gs_deg"] is None
    assert ils_aip.parse("<p>no such section</p>") == []


if __name__ == "__main__":
    n = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            n += 1
    print(f"test_ils_real: {n} tests passed")
