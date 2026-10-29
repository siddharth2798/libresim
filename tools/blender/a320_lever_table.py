"""Pure data (no bpy): the A320 flight-deck controls that get a `pivot_<name>` in interior.glb and the
`cockpit.levers` entry that drives each one in the game (aircraft/common/cockpit_levers.gd).

Frame: FlightGear model frame (x aft, y right, z up, metres), the flight deck already offset like the
glb. A pivot rotates about +X of its own frame (`kind` "rotate") or slides along it ("translate"); +X of
the pivot is `axis`, so the SIGN of a positive angle is the right-hand rule about `axis`. Origins and
axis points are read from the upstream hinge helper objects of fd_complete.ac (`*.axis`, see
tools/blender/fg_anim_summary.py on Models/FlightDeck/a320.flightdeck.xml); where upstream's helper is
skewed by a few degrees the axis is snapped to the nearest model axis.

Each row: name, objs (AC3D object names moved by it), at (pivot origin), axis, kind, children (pivots
nested inside, built earlier in the list), drive (Props expression: keys joined by " + " / " - "),
map ([[drive value, degrees or metres]] piecewise linear, clamped), lag (s, first-order low pass),
rate (max degrees/s or m/s), note. Ranges follow upstream's animation factors, except the sidestick
(real A320 +-16 deg pitch, +-20 deg roll) and the lever detents (real TLA scale).
"""

UP, DOWN, LEFT, RIGHT, FWD, AFT = (0, 0, 1), (0, 0, -1), (0, -1, 0), (0, 1, 0), (-1, 0, 0), (1, 0, 0)
THR_PIVOT = (-16.6348, 0.0, -0.2237)  # trim.axis: thrust levers and the trim wheel turn on it
TLA = [[-1.0, -23.0], [-0.1, -14.0], [-0.02, 0.0], [0.0, 0.0], [0.556, 25.0], [0.778, 35.0], [1.0, 45.0]]
MASTER = [[0.0, 35.0], [1.0, -20.0]]  # OFF leans aft, ON forward (upstream travel 55 deg)
REV_FLAP = [[-1.0, 60.0], [-0.04, 60.0], [0.0, 0.0], [1.0, 0.0]]
BOOTS = (("boot1", "level1", 2.0 / 14.0), ("boot2", "level2", 5.0 / 14.0), ("boot3", "level3", 9.0 / 14.0))


def rows():
    out = []
    for n, side, y, rev_y in ((1, "l", -0.0204, -0.0187), (2, "r", 0.0204, 0.0186)):
        out.append(dict(name=f"rev_{side}", objs=[f"rev_{side}"], at=(-16.5878, rev_y, -0.0736), axis=RIGHT, kind="rotate",
                        drive=f"controls/throttle_{n} - controls/reverse_{n}", map=REV_FLAP, rate=240.0,
                        note="reverser flap on the lever: lifts when the lever is taken below idle"))
        out.append(dict(name=f"thr_{side}", objs=[f"thr_{side}_body", f"thr_{side}_button"], at=(THR_PIVOT[0], y, THR_PIVOT[2]), axis=LEFT,
                        kind="rotate", children=[f"rev_{side}"], drive=f"controls/throttle_{n} - controls/reverse_{n}", map=TLA, rate=110.0,
                        note="thrust lever; + = forward, TLA 0..45 deg (IDLE 0, CL 25, FLX/MCT 35, TOGA 45), reverse to -23"))
    for seat, i, y in (("cpt", 1, -0.8775), ("fo", 2, 0.8774)):
        st = "" if seat == "cpt" else "_2"
        at = (-16.6701, y, -0.187)
        for part, obj, f in (("sidestick", f"sidestick_{i}", 1.0),) + tuple((b, o + st, k) for b, o, k in BOOTS):
            out.append(dict(name=f"{part}_{seat}_roll", objs=[obj], at=at, axis=FWD, kind="rotate", lag=0.07,
                            drive="controls/roll", map=[[-1.0, -20.0 * f], [1.0, 20.0 * f]],
                            note="roll (+ = right); the boot rings turn by a fraction of the stick angle (upstream 2/3/4 of 5)"))
            out.append(dict(name=f"{part}_{seat}_pitch", objs=[], at=at, axis=RIGHT, kind="rotate", lag=0.07, children=[f"{part}_{seat}_roll"],
                            drive="controls/pitch", map=[[-1.0, -16.0 * f], [1.0, 16.0 * f]], note="pitch (+ = stick aft)"))
    out += [
        dict(name="speedbrake", objs=["SpdBrk"], at=(-16.3871, -0.0813, -0.301), axis=RIGHT, kind="rotate", drive="controls/speedbrake",
             map=[[0.0, 0.0], [1.0, 45.0]], rate=70.0, note="+ = aft (extended)"),
        dict(name="flaps_lever", objs=["FlapsLever", "FlapsLever_low"], at=(-16.3871, 0.0799, -0.2825), axis=RIGHT, kind="rotate",
             drive="controls/flaps", map=[[0.0, 0.0], [1.0, 14.0], [2.0, 14.0], [3.0, 28.0], [4.0, 42.0], [5.0, 56.0]], rate=80.0,
             note="detent index 0,1,1+F,2,3,FULL; 14 deg per lever slot (1 and 1+F share one); + = aft"),
        dict(name="gear_lever", objs=["gear_lever"], at=(-17.0247, 0.1434, 0.0045), axis=RIGHT, kind="rotate", drive="controls/gear",
             map=[[0.0, 0.0], [1.0, 50.0]], rate=150.0, note="controls/gear 1 = down"),
        dict(name="parking_brake", objs=["ParkBrk"], at=(-16.2535, 0.0149, -0.2459), axis=UP, kind="rotate", drive="controls/parking_brake",
             map=[[0.0, 0.0], [1.0, 90.0]], rate=240.0, note="handle turned 90 deg"),
        dict(name="engine_master_1", objs=["Lcutoff"], at=(-16.4905, -0.0248, -0.2272), axis=RIGHT, kind="rotate", drive="controls/engine_master_1",
             map=MASTER, rate=400.0, note="engine master switch: ON = forward (the panel's ON mark is at the front)"),
        dict(name="engine_master_2", objs=["Rcutoff"], at=(-16.4905, 0.0245, -0.2272), axis=RIGHT, kind="rotate", drive="controls/engine_master_2",
             map=MASTER, rate=400.0, note="engine master switch: ON = forward (the panel's ON mark is at the front)"),
        dict(name="engine_mode", objs=["eng_mode", "eng_mode.mark"], at=(-16.4612, -0.0002, -0.2306), axis=UP, kind="rotate",
             drive="controls/engine_mode", map=[[0.0, 0.0], [1.0, 53.0], [2.0, -53.0]], rate=300.0, note="0 NORM, 1 CRANK (left), 2 IGN/START"),
        dict(name="pitch_trim", objs=["trim_1"], at=THR_PIVOT, axis=RIGHT, kind="rotate", drive="fdm/stabilizer_deg",
             map=[[-13.5, 810.0], [4.0, -240.0]], lag=0.1, note="trim wheel follows the THS (60 deg per degree, nose up = top aft)"),
        dict(name="rudder_trim", objs=["RudderTrim", "RudderTrim.mark"], at=(-16.346, 0.0171, -0.2172), axis=UP, kind="rotate",
             drive="controls/rudder_trim", map=[[-1.0, 30.0], [1.0, -30.0]], rate=120.0, note="+ = right (clockwise from above)"),
        dict(name="tiller_cpt", objs=["tiller"], at=(-16.6781, -1.0198, -0.0908), axis=UP, kind="rotate", drive="controls/tiller",
             map=[[-1.0, 75.0], [1.0, -75.0]], lag=0.08, note="+ = right"),
        dict(name="tiller_fo", objs=["tillerFo"], at=(-16.6781, 1.0194, -0.0908), axis=UP, kind="rotate", drive="controls/tiller",
             map=[[-1.0, 75.0], [1.0, -75.0]], lag=0.08, note="+ = right"),
    ]
    # rudder pedals: each pedal slides fore-aft with the rudder (the pedal of the foot that pushes goes forward) and its
    # toe brake tilts it about the hinge at its foot: names are <foot>RudderPedal<seat letter> upstream
    for foot, seat, obj, y_axis, sgn in (("l", "cpt", "LRudderPedalL", -0.6434, -1.0), ("r", "cpt", "RRudderPedalL", -0.4017, 1.0),
                                          ("l", "fo", "LRudderPedalR", 0.4014, -1.0), ("r", "fo", "RRudderPedalR", 0.6431, 1.0)):
        at = (-17.1335, y_axis, -0.519)
        out.append(dict(name=f"pedal_{foot}_{seat}_brake", objs=[obj], at=at, axis=LEFT, kind="rotate", lag=0.05,
                        drive="controls/brake_left" if foot == "l" else "controls/brake_right", map=[[0.0, 0.0], [1.0, 15.0]],
                        note="toe brake, + = toe forward"))
        out.append(dict(name=f"pedal_{foot}_{seat}", objs=[], at=at, axis=FWD, kind="translate", lag=0.08, children=[f"pedal_{foot}_{seat}_brake"],
                        drive="controls/yaw", map=[[-1.0, -0.04 * sgn], [1.0, 0.04 * sgn]], note="+ = forward (m); right rudder pushes the right pedal"))
    return out


def levers_section():
    """The draft `cockpit.levers` of aircraft.json: {pivot: {drive, map, [move], [lag], [rate]}}."""
    d = {}
    for r in rows():
        e = {"drive": r["drive"], "map": r["map"]}
        if r["kind"] == "translate":
            e["move"] = "translate"
        for k in ("lag", "rate"):
            if k in r:
                e[k] = r[k]
        d[r["name"]] = e
    return d


def write_info(path, names):
    """interior_pivots.json: the pivots built (`names`) with axes / limits and the draft cockpit.levers section."""
    import json
    from pathlib import Path
    info = {"_note": "generated by tools/blender/convert_a320_cockpit.py from a320_lever_table.py; frame = FlightGear model frame (x aft, y right, z up, m). "
            "A pivot turns (or slides, kind translate) about its own +X = axis; map rows are [drive value, degrees or metres].",
            "pivots": {}, "levers": levers_section()}
    for r in rows():
        if r["name"] in names:
            vals = [m[1] for m in r["map"]]
            info["pivots"][r["name"]] = {"at": list(r["at"]), "axis": list(r["axis"]), "kind": r["kind"], "objects": r["objs"],
                                          "children": r.get("children", []), "min": min(vals), "max": max(vals), "note": r["note"]}
    Path(path).write_text(json.dumps(info, indent=1))
