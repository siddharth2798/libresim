"""Pure data (no bpy): A320 FCU knobs and pushbuttons that get a `pivot_<name>` in interior.glb.

Frame: FlightGear model frame after the flight-deck offset OFF = (-16.47411, -0.00015, -0.09483)
(x aft, y right, z up, metres). A pivot rotates about its +X (`kind` "rotate") or slides along it
("translate"); +X is `axis`, so a positive value follows the right-hand rule about `axis` (degrees)
or moves along it (metres).

Measured from data/raw/fg/a320/Models/FlightDeck/res/fd_complete.ac via tools/blender/ac3d_parse.py
(parse, walk, to_fg, then + OFF) and Models/FlightDeck/a320.flightdeck.xml. Knob `at` is the centroid
of `<object>.axis` (4 decimals); `axis` is normalized (last vertex - first). The four hinge objects
agree at 4 decimals. None of these knobs has a `<object>.mark` sibling. Pushbutton `at` is the
primary-mesh centroid. Press direction is the normalized translate <axis> (x2-x1, y2-y1, z2-z1);
all five blocks share (-0.00962, 0, -0.00279), length 0.010016 m. The ON overlays (ap1_led, ap2_led,
a-thr_led, loc_led, appr_led) are `lamps` on that button: parented, renamed lamp_<pivot>, material
a320_fd_lamp_<pivot>. vs-sel.000 sits
about 0.35 m from the VS knob and is not part of it.

No row was skipped: hdg_sel, spd-sel, alt-sel, vs-sel, ap1, ap2, a-thr, loc and appr all exist.
"""

# Panel normal from the *.axis helpers (into the FCU, away from the pilot).
KNOB_AXIS = (-0.9574, 0.0, -0.2888)
# Same direction family, from the translate blocks rather than the hinge meshes.
BTN_AXIS = (-0.9604, 0.0, -0.2785)
BTN_TRAVEL = 0.010016  # hypot(-0.00962, 0, -0.00279); inside 0.002..0.02 m
PRESS = [[0.0, 0.0], [1.0, BTN_TRAVEL]]

# EFIS control panels (left and right of the FCU): the ND mode and range selectors. `<name>.axis` points out of the
# panel toward the pilot, so + turns the knob anticlockwise as the pilot sees it. Each mesh's `.mark` (the pointer)
# rests near 9 o'clock (92 deg anticlockwise from 12, measured from fd_complete.ac; at rest it points at LS and 10).
# Detents are 45 deg apart, as the panel's labels: mode LS 9 o'clock .. PLAN 3 o'clock (NAV at 12), range 10 at
# 9 o'clock .. 320 at half past 4 (40 at 12). Checked in the cockpit with tests/debug_a320_fcu.tscn.
EFIS_AXIS = (0.9553, 0.0, 0.2956)
EFIS_REST = -92.0  # pointer at rest, degrees clockwise from 12 o'clock
# controls/nd/mode values: 0 ARC, 1 ROSE NAV, 2 ROSE VOR, 3 ROSE LS, 4 PLAN (NdModes); clockwise position on the dial
MODE_POS = {3: -90.0, 2: -45.0, 1: 0.0, 0: 45.0, 4: 90.0}
RANGE_POS = {10: -90.0, 20: -45.0, 40: 0.0, 80: 45.0, 160: 90.0, 320: 135.0}


def _efis_map(pos):
    """[[drive value, knob degrees]] sorted by value; degrees about EFIS_AXIS (anticlockwise +), from the rest pose."""
    return [[float(v), -(pos[v] - EFIS_REST)] for v in sorted(pos)]


def _efis_rows():
    out = []
    for seat, sfx, y_mode, y_range in (("cpt", "", -0.2036, -0.1547), ("fo", "_fo", 0.2034, 0.1543)):
        out.append(dict(name=f"nd_mode_{seat}", objs=[f"nd_mode{sfx}", f"nd_mode{sfx}.mark"], at=(-16.8358, y_mode, 0.3780),
                        axis=EFIS_AXIS, kind="rotate", drive="controls/nd/mode", map=_efis_map(MODE_POS), rate=360.0,
                        note="EFIS ND mode selector: LS, VOR, NAV (ROSE), ARC, PLAN, 45 deg apart"))
        out.append(dict(name=f"nd_range_{seat}", objs=[f"nd_range{sfx}", f"nd_range{sfx}.mark"], at=(-16.8358, y_range, 0.3780),
                        axis=EFIS_AXIS, kind="rotate", drive="controls/nd/range_nm", map=_efis_map(RANGE_POS), rate=360.0,
                        note="EFIS ND range selector: 10 .. 320 NM, 36 deg apart"))
    return out


def rows():
    return [
        dict(name="hdg_sel", objs=["hdg_sel"], at=(-16.8344, -0.0490, 0.3786), axis=KNOB_AXIS, kind="rotate",
             drive="controls/fcu/hdg_deg", map=[[0.0, 0.0], [360.0, 4050.0]], rate=400.0,
             note="heading knob; 11.25 deg of knob per 1 deg of heading"),
        dict(name="spd_sel", objs=["spd-sel"], at=(-16.8312, -0.0901, 0.3796), axis=KNOB_AXIS, kind="rotate",
             drive="controls/fcu/spd_kt", map=[[100.0, -1125.0], [399.0, -4488.75]], rate=400.0,
             note="speed knob; -11.25 deg of knob per knot"),
        dict(name="alt_sel", objs=["alt-sel"], at=(-16.8311, 0.0444, 0.3794), axis=KNOB_AXIS, kind="rotate",
             drive="controls/fcu/alt_ft", map=[[100.0, 11.25], [39000.0, 4387.5]], rate=400.0,
             note="altitude knob; 11.25 deg of knob per 100 ft"),
        dict(name="vs_sel", objs=["vs-sel"], at=(-16.8348, 0.0958, 0.3785), axis=KNOB_AXIS, kind="rotate",
             drive="controls/fcu/vs_fpm", map=[[-6000.0, 675.0], [6000.0, -675.0]], rate=400.0,
             note="vertical speed knob; -11.25 deg of knob per 100 fpm"),
        dict(name="ap1", objs=["ap1"], lamps=["ap1_led"], at=(-16.8433, -0.0106, 0.3727), axis=BTN_AXIS, kind="translate",
             drive="controls/fcu/ap1", map=PRESS, rate=0.05,
             note="AP1 pushbutton; 1 = pressed in along the FCU face"),
        dict(name="ap2", objs=["ap2"], lamps=["ap2_led"], at=(-16.8433, 0.0101, 0.3727), axis=BTN_AXIS, kind="translate",
             drive="controls/fcu/ap2", map=PRESS, rate=0.05,
             note="AP2 pushbutton; 1 = pressed in along the FCU face"),
        dict(name="athr", objs=["a-thr"], lamps=["a-thr_led"], at=(-16.8369, -0.0003, 0.3522), axis=BTN_AXIS, kind="translate",
             drive="controls/fcu/athr", map=PRESS, rate=0.05,
             note="A/THR pushbutton; 1 = pressed in along the FCU face"),
        dict(name="loc", objs=["loc"], lamps=["loc_led"], at=(-16.8347, -0.0492, 0.3500), axis=BTN_AXIS, kind="translate",
             drive="controls/fcu/loc", map=PRESS, rate=0.05,
             note="LOC pushbutton; 1 = pressed in along the FCU face"),
        dict(name="appr", objs=["appr"], lamps=["appr_led"], at=(-16.8347, 0.0959, 0.3500), axis=BTN_AXIS, kind="translate",
             drive="controls/fcu/appr", map=PRESS, rate=0.05,
             note="APPR pushbutton; 1 = pressed in along the FCU face"),
    ] + _efis_rows()
