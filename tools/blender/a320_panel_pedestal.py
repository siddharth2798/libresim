"""A320 pedestal pushbuttons (no bpy). Same row shape as a320_lever_table.rows().

Frame: FlightGear model frame (x aft, y right, z up, metres) after the flight-deck offset.
A translate pivot slides along its +X, so `axis` is the unit press direction and `map` is metres.
`at` is the centroid of the primary mesh in fd_complete.ac (to_fg, then OFF), 4 decimals.
Direction is the translate <axis> segment (x2-x1, y2-y1, z2-z1) in a320.flightdeck.xml
(already FG metres; OFF is not added). Travel is that length when it is between 0.002 and
0.02 m, otherwise 0.003 m. A segment with no length (the thrust buttons' bare <y>1</y>)
presses along (0, 0, -1). Lit overlays (*_on, *_led) are left out; other objects in the
same translate animation stay, as pieces of the button.
"""
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ac3d_parse as ac  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
AC = ROOT / "data/raw/fg/a320/Models/FlightDeck/res/fd_complete.ac"
XML = ROOT / "data/raw/fg/a320/Models/FlightDeck/a320.flightdeck.xml"
OFF = (-16.47411, -0.00015, -0.09483)
INTO = (0.0, 0.0, -1.0)  # degenerate axis: press into the lever
RATE = 0.05

# mesh, pivot, drive, map knots (travel substituted for "T"), note
_SPECS = (
    ("abs_low", "autobrake_lo", "controls/autobrake", (0.0, 1.0, 2.0, 3.0), 1.0,
     "autobrake 0 off, 1 LO, 2 MED, 3 MAX; this button is in only at LO"),
    ("abs_med", "autobrake_med", "controls/autobrake", (0.0, 1.0, 2.0, 3.0), 2.0,
     "autobrake 0 off, 1 LO, 2 MED, 3 MAX; this button is in only at MED"),
    ("abs_max", "autobrake_max", "controls/autobrake", (0.0, 2.0, 3.0), 3.0,
     "autobrake 0 off, 1 LO, 2 MED, 3 MAX; this button is in only at MAX"),
    ("thr_l_button", "athr_disc_l", "controls/fcu/athr", (0.0, 1.0), 0.0,
     "A/THR instinctive disconnect, left lever: in when autothrust is off, out when on"),
    ("thr_r_button", "athr_disc_r", "controls/fcu/athr", (0.0, 1.0), 0.0,
     "A/THR instinctive disconnect, right lever: in when autothrust is off, out when on"),
)


def _overlay(name):
    return name.endswith("_on") or name.endswith("_led")


def _segment(axis_el):
    """(x2-x1, y2-y1, z2-z1) when the axis is a metre segment, else None."""
    if axis_el is None:
        return None
    def num(tag):
        text = axis_el.findtext(tag)
        return float(text) if text and text.strip() else None
    if all(num(tag) is None for tag in ("x1-m", "y1-m", "z1-m", "x2-m", "y2-m", "z2-m")):
        return None
    p1 = tuple(num(tag) or 0.0 for tag in ("x1-m", "y1-m", "z1-m"))
    p2 = tuple(num(tag) or 0.0 for tag in ("x2-m", "y2-m", "z2-m"))
    return tuple(b - a for a, b in zip(p1, p2))


def _direction(segment):
    if not segment:
        return INTO, 0.003
    length = math.hypot(*segment)
    if length < 1e-9:
        return INTO, 0.003
    axis = tuple(round(c / length, 6) for c in segment)
    travel = round(length, 6) if 0.002 <= length <= 0.02 else 0.003
    return axis, travel


def _translations(root):
    """object name -> (unit axis, travel metres, companion object names)."""
    out = {}
    for anim in root.iter("animation"):
        if (anim.findtext("type") or "").strip() != "translate":
            continue
        names = [(el.text or "").strip() for el in anim.findall("object-name")]
        names = [n for n in names if n]
        axis, travel = _direction(_segment(anim.find("axis")))
        pieces = [n for n in names if not _overlay(n)]
        for n in names:
            if n not in out:
                out[n] = (axis, travel, pieces)
    return out


def _centroids(names):
    want = set(names)
    found = {}
    _, root = ac.parse(str(AC))
    for obj, verts in ac.walk(root):
        if obj.name not in want or obj.name in found or not verts:
            continue
        fg = [ac.to_fg(v) for v in verts]
        n = float(len(fg))
        centre = tuple(sum(p[i] for p in fg) / n for i in range(3))
        found[obj.name] = tuple(round(centre[i] + OFF[i], 4) for i in range(3))
    return found


def _map(knots, pressed_at, travel):
    return [[float(k), travel if k == pressed_at else 0.0] for k in knots]


def rows():
    centres = _centroids([s[0] for s in _SPECS])
    moves = _translations(ET.parse(str(XML)).getroot())
    out = []
    for mesh, name, drive, knots, pressed_at, note in _SPECS:
        if mesh not in centres:
            raise KeyError("no primary mesh %s in %s" % (mesh, AC.name))
        axis, travel, pieces = moves.get(mesh, (INTO, 0.003, [mesh]))
        objs = [mesh] + [p for p in pieces if p != mesh]
        out.append(dict(name=name, objs=objs, at=centres[mesh], axis=axis, kind="translate",
                        drive=drive, map=_map(knots, pressed_at, travel), rate=RATE, note=note))
    return out
