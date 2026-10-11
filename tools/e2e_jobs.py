#!/usr/bin/env python3
"""E2E sweep job list (used by tools/e2e.sh). One line per job:
    <group>\t<tag>\t<expect>\t<arg>|<arg>|...
group: par (run in parallel), perf (alone), ref (reference screenshots, parallel).
expect: image expectation for the screenshot check: normal | dark | grey.
Airports/runways/stands come from data/processed (only small fields are read).
"""
import json
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data" / "processed"
CLEAR = ["--weather=clear", "--wind=270/0", "--tod=12", "--clean", "--e2e_dur=8", "--e2e_shot=ref"]


def jobs():
    rw = json.loads((DATA / "runways.json").read_text())["runways"]
    ops = json.loads((DATA / "airport_ops.json").read_text())
    ends, seen = {}, set()
    for r in rw:
        for e in r["ends"]:
            ends.setdefault(r["airport"], [])
            if e["ident"] not in ends[r["airport"]]:
                ends[r["airport"]].append(e["ident"])
    out = []
    for apt, idents in ends.items():
        for i in idents:
            out.append(("par", f"rwy_{apt}_{i}", "normal", [f"--airport={apt}", f"--runway={i}", "--e2e=spawn"]))
        out.append(("par", f"air_{apt}", "normal", [f"--airport={apt}", "--air=1500", "--e2e=spawn"]))
        if ops.get(apt, {}).get("stands"):
            out.append(("par", f"stand_{apt}", "normal", [f"--airport={apt}", "--stand", "--e2e=spawn"]))
    b27 = ["--airport=VABB", "--runway=27"]
    out.append(("par", "views_VABB", "normal", b27 + ["--e2e=views"]))
    for name, tod, exp in [("dawn", 6.5, "normal"), ("noon", 12, "normal"), ("dusk", 18.6, "dark"), ("night", 21, "dark")]:
        out.append(("par", f"tod_{name}", exp, b27 + [f"--tod={tod}", "--e2e=spawn", "--e2e_shot=tod"]))
    for wx in ["Clear", "Fair", "Scattered", "Broken", "Overcast", "Winter haze", "Monsoon"]:
        exp = "grey" if wx in ("Overcast", "Monsoon", "Winter haze", "Broken") else "normal"
        out.append(("par", "wx_" + wx.replace(" ", "_"), exp, b27 + [f"--weather={wx.lower()}", f"--e2e_wx={wx}", "--e2e=spawn", "--e2e_shot=wx"]))
    out += [
        ("par", "takeoff_VABB27", "normal", b27 + ["--e2e=takeoff"]),
        ("par", "handsoff_calm", "normal", b27 + ["--air=3000", "--weather=clear", "--wind=270/0", "--e2e=handsoff"]),
        ("par", "handsoff_fair", "normal", b27 + ["--air=3000", "--e2e=handsoff"]),
        ("par", "landing_VABB27_3nm", "normal", b27 + ["--air=950", "--e2e_nm=3", "--e2e=landing", "--e2e_timeout=500"]),
        ("par", "coldstart_VAJJ", "normal", ["--airport=VAJJ", "--cold", "--e2e=coldstart"]),
        ("par", "coldstart_VABB_stand", "normal", ["--airport=VABB", "--stand", "--e2e=coldstart"]),
        ("par", "taxi_pushback_VABB", "normal", ["--airport=VABB", "--stand", "--e2e=taxi"]),
        ("par", "panels", "normal", b27 + ["--e2e=panels"]),
        ("par", "saveload", "normal", b27 + ["--air=1500", "--e2e=saveload"]),
        ("par", "replay", "normal", b27 + ["--air=1500", "--e2e=replay"]),
        ("par", "record", "normal", b27 + ["--air=1500", "--e2e=record"]),
        ("par", "failures_VAPO", "normal", ["--airport=VAPO", "--runway=28", "--air=3000", "--e2e=failures", "--e2e_timeout=500"]),
        ("par", "nav_VABB27", "normal", b27 + ["--air=1500", "--e2e=nav"]),
        ("par", "nav_VAPO28", "normal", ["--airport=VAPO", "--runway=28", "--air=1500", "--e2e=nav"]),
        ("perf", "perf_medium", "normal", b27 + ["--air=1500", "--quality=medium", "--e2e=perf"]),
        ("perf", "perf_high", "normal", b27 + ["--air=1500", "--quality=high", "--e2e=perf"]),
    ]
    refs = [
        ("ref01_VABB27_chase", b27), ("ref02_VABB27_cockpit", b27 + ["--view=cockpit"]),
        ("ref03_VABB_stand_tower", ["--airport=VABB", "--stand", "--view=tower"]),
        ("ref04_VAJJ08_chase", ["--airport=VAJJ", "--runway=08"]), ("ref05_VAPO28_chase", ["--airport=VAPO", "--runway=28"]),
        ("ref06_VANM26_orbit", ["--airport=VANM", "--runway=26", "--view=orbit"]),
        ("ref07_VABB_air_dusk", b27 + ["--air=1500", "--tod=18.6"]),
        ("ref08_VABB27_night", b27 + ["--tod=21"]),
        ("ref09_VAAV_air_ghats", ["--airport=VAAV", "--air=2000"]),
        ("ref10_VOCI27_chase", ["--airport=VOCI", "--runway=27"]),
    ]
    for tag, a in refs:
        args = [x for x in CLEAR if not (x.startswith("--tod") and any(y.startswith("--tod") for y in a))]
        out.append(("ref", tag, "dark" if "night" in tag or "dusk" in tag else "normal", a + args + ["--e2e=spawn"]))
    return out


if __name__ == "__main__":
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    for g, tag, exp, args in jobs():
        if only and only not in tag and only != g:
            continue
        print(f"{g}\t{tag}\t{exp}\t" + "|".join(args))
