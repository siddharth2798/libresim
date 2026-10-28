"""Build a JSBSim root for the FlightGear A320-family FDE so JSBSim 1.3.3 can run it headless (reference oracle).

The upstream systems read many FlightGear-side properties (Nasal, cockpit switches, /sim, /instrumentation ...) that
do not exist outside FlightGear. We create a root under data/raw/fg/a320_root (gitignored) with symlinks to the
untrusted clone (never executed, only read by JSBSim) and a patched copy of the FDE that loads one extra system
("nasal-stubs") declaring every undefined property. Initial values come from the property defaults in A320-main.xml
and A320-200-CFM-set.xml (otherwise 0). Found by a retry loop (one stub per load error, ~700 loads); cached in
stubs.json inside the root so later runs are fast.
"""
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import common as c

RAW = c.RAW
CLONE = RAW / "fg" / "a320"
JSB_SRC = RAW / "jsbsim" / "src"
ROOT = RAW / "fg" / "a320_root"
MODEL = "A320-200-CFM"
STUBS_JSON = ROOT / "stubs.json"
PY = sys.executable
_READY = False
ERR_PATTERNS = [re.compile(p) for p in (
    r"property,? (/?[\w\[\]\-/.]+) specified", r"property (/?[\w\[\]\-/.]+) does not exist",
    r"property,? (/?[\w\[\]\-/.]+) (?:is undefined|not found|undefined)")]
PROBE = """
import sys
sys.path.insert(0, {tools!r})
import jsb_a320_sim as s
def go(**kw):
    sim = s.A320Sim(root_path=sys.argv[1]).load()
    sim.init(**kw["init"])
    for ctl, n in kw["steps"]:
        sim.set_controls(**ctl); sim.step(n)
go(init=dict(alt_ft=0, kcas=0, weight_kg=70000, on_ground=True, flaps=1), steps=[(dict(throttle=0.0, brake=1.0), 120),
   (dict(throttle=1.0, brake=0.0, pitch=0.2, rudder=0.2, flaps=1), 600), (dict(pitch=-0.5, trim=0.1, gear_down=False), 1200)])
go(init=dict(alt_ft=10000, kcas=250, weight_kg=64000, gear_down=False), steps=[(dict(throttle=0.6, roll=0.4, pitch=-0.3, speedbrake=0.5,
   trim=0.05), 600), (dict(throttle=0.0, flaps=2, gear_down=True, brake=0.5, parking_brake=1), 600), (dict(flaps=4, throttle=1.0, roll=-0.5), 600)])
go(init=dict(alt_ft=35000, mach=0.78, weight_kg=64000, gear_down=False), steps=[(dict(throttle=0.7), 600), (dict(throttle=0.0, engines=(0,)), 300)])
print("LOAD_RESULT True")
""".format(tools=str(Path(__file__).resolve().parent))


def flat_defaults(path):
    """Default property values of a FlightGear PropertyList xml: {'/a/b[1]/c': float}. Non numeric values are skipped."""
    out = {}

    def walk(e, pre):
        for ch in e:
            if not isinstance(ch.tag, str):
                continue
            p = f"{pre}/{ch.tag}" + (f"[{ch.get('n')}]" if ch.get("n") not in (None, "0") else "")
            kids = [k for k in ch if isinstance(k.tag, str)]
            if kids:
                walk(ch, p)
            elif ch.text and ch.text.strip():
                t = ch.text.strip()
                try:
                    out[p] = {"true": 1.0, "false": 0.0}.get(t) if t in ("true", "false") else float(t)
                except ValueError:
                    pass
    walk(ET.parse(path).getroot(), "")
    return out


def defaults():
    d = flat_defaults(CLONE / "A320-main.xml")
    d.update(flat_defaults(CLONE / f"{MODEL}-set.xml"))
    return d


def make_links():
    """Directory skeleton + symlinks (idempotent); returns the aircraft dir."""
    ac = ROOT / "aircraft" / MODEL
    (ac / "Systems").mkdir(parents=True, exist_ok=True)
    for link, target in ((ROOT / "engine", JSB_SRC / "engine"), (ac / "FDE", CLONE / "FDE"), (ac / "Engines", CLONE / "Engines")):
        if not link.is_symlink():
            link.symlink_to(target)
    for p in (CLONE / "Systems").iterdir():
        link = ac / "Systems" / p.name
        if not link.is_symlink():
            link.symlink_to(p)
    fde = (CLONE / "FDE" / f"{MODEL}.xml").read_text(encoding="utf-8-sig")
    fde = fde.replace('<system file="a320-core"/>', '<system file="nasal-stubs"/>\n\t<system file="a320-core"/>', 1)
    (ac / f"{MODEL}.xml").write_text(fde)
    return ac


def write_stubs(ac, stubs, dflt):
    body = "".join(f'<property value="{dflt.get("/" + s.lstrip("/"), 0.0):g}">{s}</property>\n'
                   for s in stubs)
    (ac / "Systems" / "nasal-stubs.xml").write_text(f'<?xml version="1.0"?>\n<system name="nasal-stubs">\n{body}</system>\n')


def try_load(root):
    r = subprocess.run([PY, "-I", "-c", PROBE, str(root)], capture_output=True, text=True)
    out = r.stdout + r.stderr
    return "LOAD_RESULT True" in out, out


def add_stub(name):
    """Append one more stub (called when a run fails at run time with 'property X does not exist')."""
    stubs = json.loads(STUBS_JSON.read_text()) if STUBS_JSON.exists() else []
    if name not in stubs:
        stubs.append(name)
        STUBS_JSON.write_text(json.dumps(stubs, indent=0))
        write_stubs(make_links(), stubs, defaults())
        return True
    return False


def missing_property(err_text):
    m = next((m for p in ERR_PATTERNS if (m := p.search(err_text))), None)
    return m.group(1) if m else None


def ensure(rebuild=False, verbose=True):
    """Create/refresh the root and return its path; runs the stub retry loop only when stubs.json is missing."""
    global _READY
    if _READY and not rebuild:   # already verified in this process (add_stub keeps the root valid)
        return ROOT
    dflt = defaults()
    ac = make_links()
    stubs = []
    if STUBS_JSON.exists() and not rebuild:
        stubs = json.loads(STUBS_JSON.read_text())
    write_stubs(ac, stubs, dflt)
    for i in range(3000):
        ok, out = try_load(ROOT)
        if ok:
            STUBS_JSON.write_text(json.dumps(stubs, indent=0))
            _READY = True
            if verbose and i:
                print(f"a320 root: {len(stubs)} stubs ({i} retries)")
            return ROOT
        m = next((m for p in ERR_PATTERNS if (m := p.search(out))), None)
        if not m or m.group(1) in stubs:
            raise RuntimeError("cannot load A320 FDE:\n" + out[-1500:])
        stubs.append(m.group(1))
        write_stubs(ac, stubs, dflt)
        if verbose and len(stubs) % 50 == 0:
            print("  stubs", len(stubs), flush=True)
    raise RuntimeError("too many stubs")
