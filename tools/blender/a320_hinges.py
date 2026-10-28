"""Hinge / pivot table for the A320 exterior (pure data, FlightGear model frame = structural frame, metres).

Source: the <animation> elements of upstream Models/Fuselage/fuselage.xml and a320.cfm.xml (A320-family,
GPL-2.0-only; read with tools/blender/fg_anim_summary.py), re-expressed as `pivot_<name>` empties.

Conventions (same as tools/blender/convert_c172p.py and aircraft_model.gd):
  * the pivot's local +X runs from p1 to p2 (the hinge line); the game rotates `pivot_<name>` about that +X
    by  sign * value  (value in rad, or deg for *_deg drives); rotation is right-handed in the x-aft, y-right,
    z-up frame.
  * axes are oriented so that: +angle about +y (axis pointing right) lowers a trailing edge (ailerons, flaps,
    THS: +y axes); elevators (axis -y) and rudder (axis up) use the c172's signs (-1) with the c172's fcs
    meaning (positive elevator = trailing edge down, positive rudder = right pedal); slats +y axis with sign -1
    (leading edge down when deployed); spoilers axis -y (outboard on the left wing, inboard direction on the
    right wing as upstream), +angle = panel raised.
  * `map` (optional, proposed extension of model.surfaces): piecewise-linear [[drive value, degrees], ...] of
    the upstream interpolation tables; angle is then the map output (degrees, sign still applies).
Each entry: objs (AC object names carried by the pivot), p1, p2, parent (nested pivot) and the game drive.
"""

def _s(drive, sign=1.0, **kw):
    return dict(drive=drive, sign=sign, **kw)

GEAR_NOSE_DOOR = [[0.0, 0.0], [0.1, 73.0], [0.9, 73.0], [1.0, 0.0]]
GEAR_MAIN_DOOR = [[0.0, 0.0], [0.1, 90.0], [0.9, 90.0], [1.0, 0.0]]

HINGES = {
    "aileron_L": dict(objs=["AileronL"], p1=(2.53379, -16.2917, 0.293572), p2=(1.44774, -13.2833, -0.005817), **_s("aileron", 1)),
    "aileron_R": dict(objs=["AileronR"], p1=(1.44774, 13.2833, -0.005817), p2=(2.53379, 16.2917, 0.293572), **_s("aileron", -1)),
    "stabilizer": dict(objs=["Hstabs"], p1=(15.1266, 0.0, 0.669353), p2=(15.1266, 1.0, 0.669353), **_s("stabilizer_deg", 1)),
    "elevator_L": dict(objs=["ElevatorL"], p1=(15.5724, -0.909268, 0.658597), p2=(17.3985, -6.1085, 1.48068), parent="stabilizer", **_s("elevator", -1)),
    "elevator_R": dict(objs=["ElevatorR"], p1=(17.3985, 6.1085, 1.48068), p2=(15.5724, 0.909268, 0.658597), parent="stabilizer", **_s("elevator", -1)),
    "rudder": dict(objs=["Rudder"], p1=(15.6479, 0.001397, 3.88092), p2=(16.4401, -0.000603, 5.71732), **_s("rudder", -1)),
    "flap_L1": dict(objs=["FlapL1"], p1=(-0.40885, -6.33455, -0.802401), p2=(-0.40897, -1.96981, -1.4725), **_s("flap_deg", 1)),
    "flap_L2": dict(objs=["FlapL2"], p1=(1.92808, -13.1844, -0.065162), p2=(-0.40519, -6.44122, -0.788081), **_s("flap_deg", 1)),
    "flap_R1": dict(objs=["FlapR1"], p1=(-0.40897, 1.96981, -1.4725), p2=(-0.40885, 6.33455, -0.802401), **_s("flap_deg", 1)),
    "flap_R2": dict(objs=["FlapR2"], p1=(-0.40519, 6.44122, -0.788081), p2=(1.92808, 13.1844, -0.065162), **_s("flap_deg", 1)),
    "slat_L1": dict(objs=["SlatL1"], p1=(-3.79913, -5.19121, -1.27821), p2=(-5.30738, -2.12168, -1.49252), **_s("slat_deg", -1)),
    "slat_L2": dict(objs=["SlatL2"], p1=(1.76797, -16.34866, -0.00821), p2=(-3.54786, -5.99527, -1.06999), **_s("slat_deg", -1)),
    "slat_R1": dict(objs=["SlatR1"], p1=(-5.30738, 2.11957, -1.49252), p2=(-3.79913, 5.1891, -1.27821), **_s("slat_deg", -1)),
    "slat_R2": dict(objs=["SlatR2"], p1=(-3.54786, 5.99316, -1.06999), p2=(1.76797, 16.3465, -0.00821), **_s("slat_deg", -1)),
    # spoilers 1..5 per wing (A320: 1 = ground spoiler, 2-4 = speedbrake + roll, 5 = roll); drive is per panel
    "spoiler_L1": dict(objs=["SpoilerL1"], p1=(-1.2047, -4.56129, -0.854146), p2=(-1.20839, -6.1044, -0.618676), **_s("spoiler_l1_deg")),
    "spoiler_L2": dict(objs=["SpoilerL2"], p1=(-0.98886, -6.96568, -0.556706), p2=(-0.432835, -8.51412, -0.410596), **_s("spoiler_l2_deg")),
    "spoiler_L3": dict(objs=["SpoilerL3"], p1=(-0.3862, -8.64393, -0.398151), p2=(0.129795, -10.0795, -0.262752), **_s("spoiler_l3_deg")),
    "spoiler_L4": dict(objs=["SpoilerL4"], p1=(0.175515, -10.2055, -0.250732), p2=(0.668955, -11.5802, -0.121072), **_s("spoiler_l4_deg")),
    "spoiler_L5": dict(objs=["SpoilerL5"], p1=(0.71227, -11.6975, -0.109877), p2=(1.18591, -13.0159, 0.014588), **_s("spoiler_l5_deg")),
    "spoiler_R1": dict(objs=["SpoilerR1"], p1=(-1.20923, 6.10191, -0.618062), p2=(-1.2052, 4.55902, -0.854871), **_s("spoiler_r1_deg")),
    "spoiler_R2": dict(objs=["SpoilerR2"], p1=(-0.435798, 8.51333, -0.411579), p2=(-0.98798, 6.9642, -0.557443), **_s("spoiler_r2_deg")),
    "spoiler_R3": dict(objs=["SpoilerR3"], p1=(0.126834, 10.0794, -0.263732), p2=(-0.389163, 8.64314, -0.399324), **_s("spoiler_r3_deg")),
    "spoiler_R4": dict(objs=["SpoilerR4"], p1=(0.665994, 11.5802, -0.122053), p2=(0.171844, 10.2047, -0.251904), **_s("spoiler_r4_deg")),
    "spoiler_R5": dict(objs=["SpoilerR5"], p1=(1.18224, 13.0171, 0.013605), p2=(0.708598, 11.6987, -0.110857), **_s("spoiler_r5_deg")),
    # landing gear: retraction pivots (map: gear position 0 = up .. 1 = down -> upstream table, degrees)
    "gear_nose": dict(objs=["NLGFitting", "NLGFittingPanel", "NLGDragStrutAssembly1", "NLGDragStrutAssembly2", "NLGLockStay2"],
                      p1=(-13.3241, -0.47053, -2.01238), p2=(-13.3241, 0.4696, -2.01238), **_s("gear_pos", 1, map=[[0.2, 90.0], [0.8, 0.0]])),
    "nose_steer": dict(objs=["NLGSlidingTubeAxle", "NLGFittingLower", "NLGTorqueLink1", "NLGTorqueLink2"], parent="gear_nose",
                       p1=(-13.5256, -0.027617, -3.11144), p2=(-13.5725, -0.000079, -3.42216), **_s("nose_steer_deg", 1)),
    "wheel_nose": dict(objs=["NLGWheels"], parent="nose_steer", p1=(-13.6545, 0.0, -3.96094), p2=(-13.6545, -1.0, -3.96094), **_s("wheel_nose_rad")),
    "gear_main_L": dict(objs=["MLGFittingL", "MLGLockStayL1", "MLGWingDoorL1", "MLGCablesL2", "SideStayL2", "MLGSlaveLinkL1", "MLGSlaveLinkL2",
                              "MLGTorqueLinkL1", "MLGTorqueLinkL2", "MLGSlidingTubeAxleL"],
                        p1=(-1.35004, -3.84617, -1.05491), p2=(-2.02267, -3.85672, -1.17403), **_s("gear_pos", 1, map=[[0.2, -81.11], [0.8, 0.0]])),
    "wheel_main_L": dict(objs=["MLGWheelsL"], parent="gear_main_L", p1=(-1.12983, -3.87098, -3.84487), p2=(-1.12983, -4.87098, -3.84487), **_s("wheel_main_l_rad")),
    "gear_main_R": dict(objs=["MLGFittingR", "MLGLockStayR1", "MLGWingDoorR1", "MLGCablesR2", "SideStayR2", "MLGSlaveLinkR1", "MLGSlaveLinkR2",
                              "MLGTorqueLinkR1", "MLGTorqueLinkR2", "MLGSlidingTubeAxleR"],
                        p1=(-1.35004, 3.84613, -1.05492), p2=(-2.02267, 3.85668, -1.17404), **_s("gear_pos", 1, map=[[0.2, 81.11], [0.8, 0.0]])),
    "wheel_main_R": dict(objs=["MLGWheelsR"], parent="gear_main_R", p1=(-1.12983, 3.85001, -3.84487), p2=(-1.12983, 2.85001, -3.84487), **_s("wheel_main_r_rad")),
    # gear doors
    "door_main_wing_L": dict(objs=["MLGWingDoorL2"], p1=(-1.92859, -3.97265, -1.31724), p2=(-1.17361, -3.94135, -1.23611), **_s("gear_pos", 1, map=[[0.2, 0.0], [0.8, -121.5]])),
    "door_main_wing_R": dict(objs=["MLGWingDoorR2"], p1=(-1.92859, 3.97026, -1.31724), p2=(-1.17361, 3.93896, -1.23611), **_s("gear_pos", 1, map=[[0.2, 0.0], [0.8, 121.5]])),
    "door_main_L": dict(objs=["MLGGearDoorL"], p1=(-0.959303, -0.254655, -2.39315), p2=(-2.40568, -0.254654, -2.39429), **_s("gear_pos", 1, map=[[x, -a] for x, a in GEAR_MAIN_DOOR])),
    "door_main_R": dict(objs=["MLGGearDoorR"], p1=(-0.959303, 0.254655, -2.39315), p2=(-2.40568, 0.254654, -2.39429), **_s("gear_pos", 1, map=GEAR_MAIN_DOOR)),
    "door_nose_L": dict(objs=["NLGForewardDoorL"], p1=(-15.6204, -0.52032, -2.00992), p2=(-13.8945, -0.51988, -2.15419), **_s("gear_pos", 1, map=[[x, -a] for x, a in GEAR_NOSE_DOOR])),
    "door_nose_R": dict(objs=["NLGForewardDoorR"], p1=(-15.6204, 0.51763, -2.00992), p2=(-13.8945, 0.51719, -2.15419), **_s("gear_pos", 1, map=GEAR_NOSE_DOOR)),
    "door_nose_aft_L": dict(objs=["NLGAftDoorL"], p1=(-13.4018, -0.51956, -2.17508), p2=(-14.4018, -0.51956, -2.17508), **_s("gear_pos", 1, map=[[0.0, 0.0], [0.2, 55.0], [1.0, 55.0]])),
    "door_nose_aft_R": dict(objs=["NLGAftDoorR"], p1=(-13.4018, 0.51686, -2.17508), p2=(-12.4018, 0.51686, -2.17508), **_s("gear_pos", 1, map=[[0.0, 0.0], [0.2, 55.0], [1.0, 55.0]])),
}

# engines (a320.cfm.xml): fan spin (+X = -x_model, forward), thrust reverser doors (angle = 70 deg * reverser 0..1)
ENGINE_HINGES = {
    "fan_L": dict(objs=["FanLCFM56L"], p1=(-6.66773, -5.63082, -2.26943), p2=(-7.66773, -5.63082, -2.26943), **_s("n1_spin", 1)),
    "fan_R": dict(objs=["FanLCFM56R"], p1=(-6.66773, 5.62871, -2.26943), p2=(-7.66773, 5.62871, -2.26943), **_s("n1_spin", 1)),
}
for _side, _sgn in (("L", 1), ("R", -1)):
    _ys = {"L": [(-6.25156, -6.29771), (-6.29253, -6.2496), (-5.01022, -4.96408), (-4.96919, -5.01209)],
           "R": [(5.01008, 4.96393), (4.96912, 5.01204), (6.25142, 6.29756), (6.29245, 6.24955)]}[_side]
    _zs = [(-1.65547, -1.71849), (-2.82287, -2.88363), (-1.6555, -1.71852), (-2.82264, -2.8834)]
    _xs = [(-4.7738, -4.77475), (-4.77785, -4.77731), (-4.7738, -4.77475), (-4.778, -4.77746)]
    _fac = {"L": [-70, -70, 70, 70], "R": [-70, -70, 70, 70]}[_side]
    for _i in range(4):
        ENGINE_HINGES["reverser_%s%d" % (_side, _i + 1)] = dict(
            objs=["Reverser%sDoor%d" % (_side, _i + 1)], p1=(_xs[_i][0], _ys[_i][0], _zs[_i][0]), p2=(_xs[_i][1], _ys[_i][1], _zs[_i][1]),
            **_s("reverser", 1, map=[[0.0, 0.0], [1.0, float(_fac[_i])]]))

EXT_DROP_SUFFIX = (".Inner", ".Placards")
EXT_DROP_PREFIX = ("Static-Elements", "ULD", "DoorHinge", "Rat", "CargoDoorActuators", "GearLDoorActuator", "SpoilerActuator",
                   "FlapMechanism", "WingtipFence", "navglass", "WindshildWiper", "NurbsPath", "MLGLockstayActuator", "FlapL2.001",
                   "ReverserActuators", "FanSpinning")
WHEELS = ("NLGWheels", "MLGWheelsL", "MLGWheelsR")


def keep_exterior(name):
    return not (name.endswith(EXT_DROP_SUFFIX) or name.startswith(EXT_DROP_PREFIX) or ".Placards" in name)
