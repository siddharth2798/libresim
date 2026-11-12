"""The parts of one A320 passenger door (tools/blender/a320_door.py), in door coordinates (a320_door_geom.Skin):
a aft of the forward edge, h above the sill, d inboard of the outer face. Layout of the inner face after the cabin
photo of an A320 door: header panel with the viewing window, the slide-arming housing on the forward (hinge) side
with its lever up (DISARMED), safety pin and red streamer, the door control handle on the aft side, the slide
bustle across the bottom with its pressure gauge, kick strip and stowed girt bar. States (normal ground opening):
closed = handle down, lock indicator green; open = handle up (the game turns `<id>_handle`), the rest unchanged.
"""
import math

from mathutils import Vector

from a320_door_geom import EPS_OUT, Part, rr_rows, boundary

T = 0.11  # door thickness, outer skin to inner lining
R = 0.12  # outline corner radius
WALL = 0.26  # doorway lining depth (fuselage wall + trim), horizontal
LIP = 0.045  # frame lip each side: 0.9 m painted outline, 0.81 m clear opening
ARM_H = 0.71  # hinge arm height above the sill (between the slide bustle and the viewing window)
ATTACH_A = 0.57  # where the arm meets the door (aft of its forward edge); the pivot lands 0.07 aft of the edge
WIN = (0.57, 1.03)  # viewing window centre, where the painted door on the exterior atlas has it
HANDLE_HINGE = (0.76, 1.24)
# arm path in its own frame at the closed door: (s along the door aft, q outboard), as fractions of the arm length;
# it bows inboard so that, swung 165 deg, it clears the forward frame edge
ARM_PATH = [(0.0, 0.0), (0.02, -0.26), (0.10, -0.44), (0.28, -0.50), (0.56, -0.48), (0.80, -0.34), (0.94, -0.16), (1.0, 0.0)]

MATS = {  # name: (sRGB, roughness, metallic)
    "door_paint": ("#eeeff0", 0.45, 0.0),
    "door_lining": ("#d8d8d4", 0.7, 0.0),
    "door_seam": ("#8a8a86", 0.7, 0.0),
    "door_seal": ("#1c1c1e", 0.85, 0.0),
    "door_glass": ("#0e141b", 0.08, 0.0),
    "door_metal": ("#9a9ca0", 0.4, 0.6),
    "door_arm": ("#b9bbbd", 0.5, 0.2),
    "door_dark": ("#2b2b2d", 0.8, 0.0),
    "door_red": ("#c8141a", 0.55, 0.0),
    "door_yellow": ("#e8c21a", 0.55, 0.0),
    "door_green": ("#2db84a", 0.4, 0.0),
    "door_placard": ("#f2f2ee", 0.6, 0.0),
    "door_lens_red": ("#5a0d0d", 0.1, 0.0),
    "door_lens_white": ("#c4c4c0", 0.1, 0.0),
    "cabin_floor": ("#5f6267", 0.95, 0.0),
    "cabin_wall": ("#dcdad4", 0.75, 0.0),
    "cabin_ceiling": ("#e8e6e0", 0.75, 0.0),
    "cabin_galley": ("#a7adb4", 0.45, 0.5),
    "cabin_mat": ("#3e4145", 0.9, 0.0),
    "door_mask": ("#000000", 1.0, 0.0),
}
M = {k: i for i, k in enumerate(MATS)}


def leaf(s, w, hh):
    """The door itself: curved outer skin, edge with seal, inner lining and its fittings."""
    p = Part(s)
    rows = rr_rows(0.0, w, 0.0, hh, R, R, 6, 10)
    out_g = p.grid(rows, 0.0, M["door_paint"])
    l0 = [out_g[i][j] for (i, j) in boundary(rows)]
    l1, l2 = p.loop(rows, 0.012), p.loop(rows, 0.07)
    in_g = p.grid(rows, T, M["door_lining"])
    l3 = [in_g[i][j] for (i, j) in boundary(rows)]
    p.band(l0, l1, M["door_paint"])
    p.band(l1, l2, M["door_seal"])
    p.band(l2, l3, M["door_lining"])
    outer_face(p, w)
    inner_face(p, w)
    return p


def outer_face(p, w):
    """Viewing window, the outside handle flap (red outline), EXIT and HOOK marks: where the painted door has them."""
    wa, wh = WIN
    n = p.s.frame(wa, wh)[1]
    win = rr_rows(wa - 0.075, wa + 0.075, wh - 0.075, wh + 0.075, 0.06, 0.06, 2, 2)
    glass = rr_rows(wa - 0.058, wa + 0.058, wh - 0.058, wh + 0.058, 0.045, 0.045, 2, 2)
    p.band(p.loop(win, -0.002), p.loop(glass, -0.002), M["door_seam"], n)
    p.grid(glass, -0.002, M["door_glass"], n)
    flap = rr_rows(0.27, 0.41, 0.84, 1.18, 0.02, 0.02, 1, 3)
    p.band(p.loop(flap, -0.0015), p.loop(rr_rows(0.278, 0.402, 0.848, 1.172, 0.014, 0.014, 1, 3), -0.0015),
           M["door_red"], p.s.frame(0.34, 1.0)[1])
    p.sheet(0.31, 0.37, 1.10, 1.15, -0.0016, M["door_dark"], toward_cabin=False)
    p.sheet(0.34, 0.42, 1.27, 1.30, -0.0016, M["door_red"], toward_cabin=False)
    p.sheet(0.53, 0.61, 0.82, 0.84, -0.0016, M["door_red"], toward_cabin=False)


def inner_face(p, w):
    ti = T - 0.004  # boxes start just inside the lining
    wa, wh = WIN
    p.box(0.05, w - 0.05, 1.32, 1.79, ti, T + 0.012, M["door_lining"], r=0.10, bev=0.006, nc=4, nm=3)  # header
    p.box(wa - 0.105, wa + 0.105, wh - 0.105, wh + 0.105, ti, T + 0.03, M["door_seam"], r=0.07, bev=0.006)  # window
    p.sheet(wa - 0.085, wa + 0.085, wh - 0.085, wh + 0.085, T + 0.031, M["door_glass"], r=0.05, nc=2, nm=2)
    # cabin pressure warning (red triangle) and slide armed (white) lights just under the window: unlit lenses
    n, d = p.s.frame(0.53, 0.89)[1], T + 0.002
    p.poly([p.s.pt(0.51, 0.875, d), p.s.pt(0.55, 0.875, d), p.s.pt(0.53, 0.91, d)], M["door_lens_red"], -n)
    p.sheet(0.585, 0.635, 0.875, 0.905, d, M["door_lens_white"])
    # slide arming housing on the forward side: lever up = DISARMED, safety pin in, red streamer
    p.box(0.06, 0.40, 0.64, 1.12, ti, T + 0.09, M["door_lining"], bev=0.01)
    p.box(0.27, 0.30, 1.10, 1.21, T + 0.06, T + 0.085, M["door_seam"])
    p.box(0.262, 0.308, 1.19, 1.225, T + 0.055, T + 0.09, M["door_red"], bev=0.003)
    p.cylinder(p.s.pt(0.34, 1.07, T + 0.088), p.s.pt(0.34, 1.07, T + 0.118), 0.006, M["door_metal"], 8)
    p.sheet(0.328, 0.352, 0.76, 1.065, T + 0.093, M["door_red"], nm=3)
    p.sheet(0.337, 0.343, 0.80, 1.03, T + 0.0935, M["door_placard"])
    p.sheet(0.10, 0.20, 0.98, 1.04, T + 0.0905, M["door_yellow"])
    p.sheet(0.10, 0.22, 0.86, 0.92, T + 0.0905, M["door_placard"])
    p.disc(0.22, 1.17, 0.018, T + 0.002, M["door_seam"])
    p.disc(0.22, 1.17, 0.012, T + 0.003, M["door_green"])  # arming indicator: DISARMED
    # arm fitting, handle base, OPEN placard with its red arrow, the small red lever, placards
    p.box(ATTACH_A - 0.035, ATTACH_A + 0.035, ARM_H - 0.11, ARM_H + 0.11, ti, T + 0.035, M["door_metal"])
    p.box(0.72, 0.80, 1.19, 1.29, ti, T + 0.05, M["door_seam"])
    p.sheet(0.81, 0.875, 1.00, 1.16, T + 0.002, M["door_placard"])
    p.sheet(0.839, 0.847, 1.02, 1.115, T + 0.0025, M["door_red"])
    n, d = p.s.frame(0.843, 1.13)[1], T + 0.0025
    p.poly([p.s.pt(0.828, 1.115, d), p.s.pt(0.858, 1.115, d), p.s.pt(0.843, 1.145, d)], M["door_red"], -n)
    p.box(0.735, 0.755, 0.63, 0.66, ti, T + 0.03, M["door_metal"])
    p.box(0.70, 0.80, 0.633, 0.657, T + 0.03, T + 0.05, M["door_red"], bev=0.003)
    p.sheet(0.64, 0.71, 0.76, 0.80, T + 0.002, M["door_placard"])
    p.sheet(0.64, 0.71, 0.70, 0.74, T + 0.002, M["door_yellow"])
    # slide bustle across the bottom: pressure gauge, kick strip, stowed girt bar under it
    p.box(0.03, w - 0.03, 0.025, 0.58, ti, T + 0.22, M["door_lining"], r=0.04, bev=0.05, nc=4, nm=3)
    p.sheet(0.09, w - 0.09, 0.08, 0.12, T + 0.2205, M["door_dark"])
    p.disc(0.18, 0.48, 0.026, T + 0.2205, M["door_placard"])
    p.disc(0.18, 0.48, 0.017, T + 0.221, M["door_glass"])
    p.cylinder(p.s.pt(0.07, 0.014, T + 0.19), p.s.pt(w - 0.07, 0.014, T + 0.19), 0.012, M["door_metal"], 8)
    for a in (0.09, w - 0.09):
        p.box(a - 0.02, a + 0.02, 0.0, 0.03, ti, T + 0.20, M["door_metal"], bev=0.003)


def lock_flag(s, locked):
    """Door locking indicator by the handle: green LOCKED or red UNLOCKED (the game shows one)."""
    p = Part(s)
    p.sheet(0.64, 0.69, 1.22, 1.25, T + 0.003, M["door_green" if locked else "door_red"])
    return p


def handle(s):
    """The door control handle, modelled down (CLOSED / LOCKED). Origin: its hinge."""
    p = Part(s)
    a, h = HANDLE_HINGE
    p.box(a - 0.018, a + 0.018, 0.88, h + 0.01, T + 0.015, T + 0.045, M["door_seam"], nm=3)
    p.box(a - 0.025, a + 0.025, 0.84, 0.92, T + 0.01, T + 0.055, M["door_dark"])
    return p, s.pt(a, h, T + 0.03)


def arm(s, w):
    """The hinge arm (gooseneck): pivots on a pin in the forward door frame, its end on the door's fitting.
    Origin: the pivot. The pivot is the end point moved one arm length forward (CabinDoorPanel arm = w/2 + 0.05),
    so the door, carried at that radius, stays parallel to the skin. Returns (part, pivot, end)."""
    L = w / 2 + 0.05
    end = s.pt(ATTACH_A, ARM_H, T + 0.035)
    piv = end - Vector((L, 0.0, 0.0))
    inboard = s.inward()
    p = Part(s)
    path = [piv + Vector((L * u, 0.0, 0.0)) - inboard * (L * q) for (u, q) in ARM_PATH]
    p.tube(path, 0.03, 0.09, M["door_arm"])
    p.cylinder(piv - Vector((0, 0, 0.15)), piv + Vector((0, 0, 0.15)), 0.034, M["door_metal"], 12)
    return p, piv, end


def frame(s, w, hh, piv):
    """The open doorway, drawn only through the portal (the skin has no hole): the cut edge of the skin, the frame
    lip with its stops, the lined doorway with the dark sill plate and assist handles, the arm's pin brackets, and
    a lit galley vestibule beyond so the opening is never a flat dark rectangle."""
    p = Part(s)
    ins = s.inward()
    centre = s.pt(w / 2, hh / 2, 0.0) + ins * (WALL / 2)
    toward = lambda q: centre - sum((p.v[i] for i in q), Vector()) / len(q)
    rim = rr_rows(0.0, w, 0.0, hh, R, R, 6, 10)
    opening = rr_rows(LIP, w - LIP, 0.0, hh - 0.02, 0.025, 0.10, 6, 10)
    d_lip = EPS_OUT + 0.015
    p.band(p.loop(rim, EPS_OUT - 0.015), p.loop(rim, d_lip), M["door_paint"], toward)
    l_open = p.loop(opening, d_lip)
    n_mid = s.frame(w / 2, hh / 2)[1]
    p.band(p.loop(rim, d_lip), l_open, M["door_metal"], n_mid)
    l_in = p.loop(opening, fn=lambda a, h: s.pt(a, h, d_lip) + ins * WALL)
    nc = len(opening[0]) - 1
    p.band(l_open, l_in, M["door_lining"], toward, mat_fn=lambda k: M["door_dark"] if k < nc else M["door_lining"])
    for a0 in (0.006, w - 0.038):  # door stops on the frame lip
        for h in (0.35, 0.8, 1.25, 1.6):
            p.box(a0, a0 + 0.032, h - 0.03, h + 0.03, d_lip + 0.004, d_lip - 0.016, M["door_dark"], bev=0.003)
    for a in (LIP + 0.035, w - LIP - 0.035):  # assist handles at the inner end of the lining
        b0, b1 = s.pt(a, 0.95, d_lip) + ins * (WALL - 0.05), s.pt(a, 1.40, d_lip) + ins * (WALL - 0.05)
        p.cylinder(b0, b1, 0.014, M["door_metal"], 8)
        side = 1.0 if a < w / 2 else -1.0
        for b in (b0, b1):
            p.cylinder(b, b + Vector((-side * 0.04, 0, 0)), 0.009, M["door_metal"], 6)
    wall_x = s.xf + LIP
    for dz in (-0.165, 0.155):  # pin brackets from the forward frame to the arm pin
        p.tube([Vector((wall_x, piv.y, piv.z + dz)), Vector((piv.x + 0.02, piv.y, piv.z + dz))], 0.03, 0.006, M["door_metal"])
    vestibule(p, s, w)
    return p


def vestibule(p, s, w):
    """Galley area inside the door: floor, ceiling, fore / aft walls and a back wall with trolley fronts."""
    side, z0 = s.side, s.z0
    y_near = s.frame(w / 2, 0.0)[0].y - side * 0.22
    y_far = y_near - side * 1.7
    x0, x1, z1 = s.xf - 0.55, s.xf + w + 0.55, z0 + 2.15
    c = Vector(((x0 + x1) / 2, (y_near + y_far) / 2, (z0 + z1) / 2))
    V = lambda x, y, z: Vector((x, y, z))
    faces = [
        ([V(x0, y_near, z0), V(x1, y_near, z0), V(x1, y_far, z0), V(x0, y_far, z0)], "cabin_floor"),
        ([V(x0, y_near, z1), V(x1, y_near, z1), V(x1, y_far, z1), V(x0, y_far, z1)], "cabin_ceiling"),
        ([V(x0, y_far, z0), V(x1, y_far, z0), V(x1, y_far, z1), V(x0, y_far, z1)], "cabin_wall"),
        ([V(x0, y_near, z0), V(x0, y_far, z0), V(x0, y_far, z1), V(x0, y_near, z1)], "cabin_wall"),
        ([V(x1, y_near, z0), V(x1, y_far, z0), V(x1, y_far, z1), V(x1, y_near, z1)], "cabin_wall"),
    ]
    for pts, m in faces:
        p.poly(pts, M[m], c - sum(pts, Vector()) / 4)
    ym = y_near - side * 0.75  # entry mat inside the door: gives the floor an edge to read by
    p.poly([V(x0 + 0.3, y_near, z0 + 0.005), V(x1 - 0.3, y_near, z0 + 0.005), V(x1 - 0.3, ym, z0 + 0.005), V(x0 + 0.3, ym, z0 + 0.005)],
           M["cabin_mat"], Vector((0, 0, 1)))
    yb = y_far + side * 0.012
    out = Vector((0, side, 0))
    for i in range(3):  # trolley fronts, worktop, upper stowage
        xa = x0 + 0.25 + i * (x1 - x0 - 0.5) / 3
        xb = xa + (x1 - x0 - 0.5) / 3 - 0.03
        p.poly([V(xa, yb, z0 + 0.10), V(xb, yb, z0 + 0.10), V(xb, yb, z0 + 1.02), V(xa, yb, z0 + 1.02)], M["cabin_galley"], out)
    p.poly([V(x0, yb, z0), V(x1, yb, z0), V(x1, yb, z0 + 0.08), V(x0, yb, z0 + 0.08)], M["door_dark"], out)  # toe kick
    p.poly([V(x0 + 0.2, yb, z0 + 1.04), V(x1 - 0.2, yb, z0 + 1.04), V(x1 - 0.2, yb, z0 + 1.10), V(x0 + 0.2, yb, z0 + 1.10)], M["door_dark"], out)


def mask(s, w, hh):
    """The portal: the painted door outline 15 mm outside the skin (clear of the skin's facets, which bulge up to ~6 mm
    between the sampled points). The game makes it write the stencil only."""
    p = Part(s)
    p.grid(rr_rows(0.0, w, 0.0, hh, R, R, 6, 10), EPS_OUT - 0.015, M["door_mask"], s.frame(w / 2, hh / 2)[1])
    return p
