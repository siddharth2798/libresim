"""Pure data (no bpy): A320 overhead light switches and pushbuttons that get a `pivot_<name>` in
interior.glb, and the `cockpit.levers` drive for each one (same row shape as a320_lever_table.py).

Frame: FlightGear model frame after the flight-deck offset OFF = (-16.47411, -0.00015, -0.09483)
(x aft, y right, z up, metres). A pivot rotates about its +X (`kind` "rotate") or slides along it
("translate"); +X is `axis`.

Rotary `at` is the centroid of `<Name>.axis` world vertices (ac3d_parse to_fg + OFF, 4 decimals) and
`axis` is that helper's last vertex minus its first, normalized. Upstream angle is property * factor
+ offset-deg. These drives are 0/1 (nav + logo sums to 0, 1 or 2), so a two-position switch maps
[[0, offset], [1, offset + factor]]. Pushbutton `at` is the centroid of the primary mesh. The slide
direction is that control's translate <axis> in a320.flightdeck.xml (x2-x1, y2-y1, z2-z1), already
FG metres, normalized; travel is the vector length (0.01 m, inside 0.002..0.02).

Skipped AC objects: none. No `.mark` helper exists for these switches. No `_led` / `_on` duplicate
sits beside a base mesh in the animation, so the cap parts (1F, 2O, 1A) ride with the body.
"""

RIGHT = (0.0, 1.0, 0.0)  # every <Name>.axis helper is a pure +Y segment
PRESS = (-0.365, 0.0, 0.931)  # unit (x2-x1, 0, z2-z1); the same XML axis on every pushbutton
LIGHT = [[0.0, -30.0], [1.0, 30.0]]  # factor 60, offset-deg -30
NAV = [[0.0, -35.0], [1.0, 0.0], [2.0, 35.0]]  # factor 35, offset-deg -35, three steps
PRESS_MAP = [[0.0, 0.0], [1.0, 0.01]]


def _rot(name, objs, at, drive, note, amap=None):
    return dict(name=name, objs=objs, at=at, axis=RIGHT, kind="rotate", drive=drive,
                map=LIGHT if amap is None else amap, rate=240.0, note=note)


def _btn(name, objs, at, drive, note):
    return dict(name=name, objs=objs, at=at, axis=PRESS, kind="translate", drive=drive,
                map=PRESS_MAP, rate=0.05, note=note)


def rows():
    return [
        _rot("beacon_lt", ["BeaconLtSwtch"], (-16.6114, -0.1009, 0.8115), "controls/lights/beacon",
             "beacon; OFF -30 deg, ON +30"),
        _rot("strobe_lt", ["StrobeLtSwtch"], (-16.6114, -0.1303, 0.8115), "controls/lights/strobe",
             "strobe; OFF -30 deg, ON +30"),
        _rot("wing_lt", ["WingLtSwtch"], (-16.6114, -0.0708, 0.8115), "controls/lights/wing",
             "wing lights; OFF -30 deg, ON +30"),
        _rot("landing_lt", ["LandingLtSwtch"], (-16.6572, -0.101, 0.7935), "controls/lights/landing",
             "left landing light; shares the drive with the right switch"),
        _rot("landing_lt_r", ["LandingLtRSwtch"], (-16.6572, -0.0718, 0.7935), "controls/lights/landing",
             "right landing light; moves with the left switch"),
        _rot("nose_lt", ["NoseLtSwtch"], (-16.6572, -0.0428, 0.7935), "controls/lights/taxi",
             "nose / taxi light; OFF -30 deg, ON +30"),
        _rot("turnoff_lt", ["TurnoffLtSwtch"], (-16.6572, -0.1303, 0.7935), "controls/lights/rwy_turnoff",
             "runway turnoff lights; OFF -30 deg, ON +30"),
        _rot("nav_logo_lt", ["NavLogoLtSwtch"], (-16.6114, -0.0428, 0.8115),
             "controls/lights/nav + controls/lights/logo",
             "0 off, 1 nav or logo, 2 both; upstream factor 35, offset-deg -35", NAV),
        _btn("apu_master", ["APUMasterBtn", "APUMasterBtn1F", "APUMasterBtn2O"], (-16.6124, -0.0001, 0.8145),
             "controls/apu_master", "APU master; 10 mm along the panel normal"),
        _btn("apu_start", ["APUStartBtn", "APUStartBtn1A", "APUStartBtn2O"], (-16.6577, -0.0001, 0.7967),
             "controls/apu_start", "APU start, held; 10 mm along the panel normal"),
        _btn("wing_anti_ice", ["WingAntiIceBtn", "WingAntiIceBtn1F", "WingAntiIceBtn2O"],
             (-16.5674, -0.1302, 0.8322), "controls/anti_ice/wing", "wing anti-ice; 10 mm along the panel normal"),
        _btn("eng1_anti_ice", ["Eng1AntiIceBtn", "Eng1AntiIceBtn1F", "Eng1AntiIceBtn2O"],
             (-16.5674, -0.0725, 0.8322), "controls/anti_ice/eng_1", "engine 1 anti-ice; 10 mm along the panel normal"),
        _btn("eng2_anti_ice", ["Eng2AntiIceBtn", "Eng2AntiIceBtn1F", "Eng2AntiIceBtn2O"],
             (-16.5674, -0.0398, 0.8322), "controls/anti_ice/eng_2", "engine 2 anti-ice; 10 mm along the panel normal"),
    ]
