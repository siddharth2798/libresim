"""A320 overhead system controls (no bpy) that get a `pivot_<name>` in interior.glb: the ELEC, HYD, FUEL and
AIR pushbuttons and the SIGNS rotaries, each driving the switch prop its system already reads
(systems/airliner_electrical.gd, airliner_hydraulics.gd, airliner_fuel.gd, airliner_cabin.gd,
airliner_warnings.gd). Same row shape as a320_lever_table.rows().

Pushbuttons: `at` is the centroid of the primary mesh in fd_complete.ac (to_fg, then OFF); direction and
travel are that mesh's translate <axis> segment in a320.flightdeck.xml (a320_panel_pedestal helpers).
A pushbutton is in when its prop is on (1) and out when off (0), like the real latching buttons.
The two-word cap (`<mesh>2O`, or `<mesh>O` on the APU GEN button) is the lamp: it reads OFF on most
buttons and lights when the switch is off; on EXT PWR, the yellow electric pump, X FEED and APU BLEED it
reads ON and lights when on (`lamp_lit`, copied into CockpitLamps._ON by hand).
The fuel panel has two pumps per tank and the sim one pump switch per tank: both buttons of a tank share
its prop (like the left and right landing light switches).
Rotaries: `at` is the centroid of the `<Name>.axis` helper and `axis` its last vertex minus its first,
normalized; upstream angle factor 60, offset -30 (OFF -30 deg, ON +30), like the light switches.
"""
import math
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ac3d_parse as ac  # noqa: E402
import a320_panel_pedestal as ped  # noqa: E402

RATE = 0.05
LIGHT = [[0.0, -30.0], [1.0, 30.0]]

# mesh, pivot, drive, lamp cap, lamp lit at (0 = OFF caption, 1 = ON caption), note
BUTTONS = (
    ("BatteryBtn1", "bat1", "controls/electrical/bat1", "BatteryBtn12O", 0, "BAT 1; OFF lights when off"),
    ("BatteryBtn2", "bat2", "controls/electrical/bat2", "BatteryBtn22O", 0, "BAT 2; OFF lights when off"),
    ("Gen1Btn", "gen1", "controls/electrical/gen1", "Gen1Btn2O", 0, "GEN 1; OFF lights when off"),
    ("Gen2Btn", "gen2", "controls/electrical/gen2", "Gen2Btn2O", 0, "GEN 2; OFF lights when off"),
    ("APUGenBtn", "apu_gen", "controls/electrical/apu_gen", "APUGenBtnO", 0, "APU GEN; OFF lights when off"),
    ("ExtPwrBtn", "ext_pwr", "controls/electrical/ext_pwr", "ExtPwrBtn2O", 1, "EXT PWR; ON lights when on"),
    ("GreenEngPump2", "green_edp", "controls/hyd/green_edp", "GreenEngPump22O", 0, "GREEN ENG 1 PUMP; OFF lights when off"),
    ("YellowEngPump", "yellow_edp", "controls/hyd/yellow_edp", "YellowEngPump2O", 0, "YELLOW ENG 2 PUMP; OFF lights when off"),
    ("BlueElecPump", "blue_epump", "controls/hyd/blue_epump", "BlueElecPump2O", 0, "BLUE ELEC PUMP (AUTO); OFF lights when off"),
    ("YellowElecPump", "yellow_epump", "controls/hyd/yellow_epump", "YellowElecPump2O", 1, "YELLOW ELEC PUMP; ON lights when on"),
    ("PTU2", "ptu", "controls/hyd/ptu", "PTU22O", 0, "PTU (AUTO); OFF lights when off"),
    ("LFuelTank1Btn", "fuel_l1", "controls/fuel/pump_left", "LFuelTank1Btn2O", 0, "L TK PUMP 1; shares the left pump switch"),
    ("LFuelTank2Btn", "fuel_l2", "controls/fuel/pump_left", "LFuelTank2Btn2O", 0, "L TK PUMP 2; shares the left pump switch"),
    ("CFuelTank1Btn", "fuel_c1", "controls/fuel/pump_centre", "CFuelTank1Btn2O", 0, "CTR TK PUMP 1; shares the centre pump switch"),
    ("CFuelTank2Btn", "fuel_c2", "controls/fuel/pump_centre", "CFuelTank2Btn2O", 0, "CTR TK PUMP 2; shares the centre pump switch"),
    ("RFuelTank1Btn", "fuel_r1", "controls/fuel/pump_right", "RFuelTank1Btn2O", 0, "R TK PUMP 1; shares the right pump switch"),
    ("RFuelTank2Btn", "fuel_r2", "controls/fuel/pump_right", "RFuelTank2Btn2O", 0, "R TK PUMP 2; shares the right pump switch"),
    ("FuelXFeedBtn", "xfeed", "controls/fuel/crossfeed", "FuelXFeedBtn2O", 1, "fuel X FEED; ON lights when on"),
    ("Eng1BleedBtn", "bleed1", "controls/bleed/eng1", "Eng1BleedBtn2O", 0, "ENG 1 BLEED; OFF lights when off"),
    ("Eng2BleedBtn", "bleed2", "controls/bleed/eng2", "Eng2BleedBtn2O", 0, "ENG 2 BLEED; OFF lights when off"),
    ("APUBleedBtn", "apu_bleed", "controls/bleed/apu", "APUBleedBtn2O", 1, "APU BLEED; ON lights when on"),
    ("ACPack1Btn", "pack1", "controls/bleed/pack1", "ACPack1Btn2O", 0, "PACK 1; OFF lights when off"),
    ("ACPack2Btn", "pack2", "controls/bleed/pack2", "ACPack2Btn2O", 0, "PACK 2; OFF lights when off"),
)

# helper-axis mesh, pivot, drive, note
ROTARIES = (
    ("SeatBeltSwtch", "seatbelt_sw", "controls/signs/seatbelts", "SEAT BELTS sign; OFF -30 deg, ON +30"),
    ("NoSmokingSwtch", "no_smoking_sw", "controls/signs/no_smoking", "NO SMOKING sign; OFF -30 deg, ON +30"),
)


def lamp_lit():
    """pivot -> value of its drive that lights its cap (for CockpitLamps)."""
    return {name: float(lit) for _, name, _, _, lit, _ in BUTTONS}


def _axis_helpers(names):
    """`<Name>.axis` helper -> (centroid with OFF, unit last-minus-first vertex)."""
    want = {n + ".axis" for n in names}
    out = {}
    _, root = ac.parse(str(ped.AC))
    for obj, verts in ac.walk(root):
        if obj.name not in want or obj.name in out or len(verts) < 2:
            continue
        fg = [ac.to_fg(v) for v in verts]
        n = float(len(fg))
        centre = tuple(round(sum(p[i] for p in fg) / n + ped.OFF[i], 4) for i in range(3))
        d = tuple(fg[-1][i] - fg[0][i] for i in range(3))
        length = math.sqrt(sum(c * c for c in d)) or 1.0
        out[obj.name[:-5]] = (centre, tuple(round(c / length, 6) for c in d))
    return out


def rows():
    centres = ped._centroids([b[0] for b in BUTTONS])
    moves = ped._translations(ET.parse(str(ped.XML)).getroot())
    out = []
    for mesh, name, drive, lamp, _lit, note in BUTTONS:
        if mesh not in centres:
            raise KeyError("no primary mesh %s in %s" % (mesh, ped.AC.name))
        axis, travel, pieces = moves.get(mesh, (ped.INTO, 0.003, [mesh]))
        objs = [mesh] + [p for p in pieces if p != mesh]
        if lamp not in objs:
            objs.append(lamp)
        out.append(dict(name=name, objs=objs, lamps=[lamp], at=centres[mesh], axis=axis, kind="translate",
                        drive=drive, map=[[0.0, 0.0], [1.0, travel]], rate=RATE, note=note))
    helpers = _axis_helpers([r[0] for r in ROTARIES])
    for mesh, name, drive, note in ROTARIES:
        if mesh not in helpers:
            raise KeyError("no axis helper %s.axis in %s" % (mesh, ped.AC.name))
        at, axis = helpers[mesh]
        out.append(dict(name=name, objs=[mesh], at=at, axis=axis, kind="rotate", drive=drive, map=LIGHT,
                        rate=240.0, note=note))
    return out


if __name__ == "__main__":
    for r in rows():
        print(r["name"], r["at"], r["axis"], r["objs"], r["map"])
