"""Close-up nacelle lip, gear-door hinges, fan spinner and fan-blade blur on exterior.glb.

Blender -b --factory-startup --python tools/blender/a320_nacelle.py

Works in Blender world after the glTF import (+X aft, +Y right, +Z up). The inlet lip is
measured: rays run forward of each fan pivot and the most forward body hit at each angle
is the rim. Nothing is placed from a fixed radius. Export is a320_scene.export_glb.
Stops without writing if detail_inlet_l already exists. Restores the glb if a node drops
or a pivot_* moves (1 mm / 0.1 deg).

Triangle budget, quads counted as two: lip 20x8 tube x2 = 640, eight doors x3 barrels
x24 = 576, spinner cone x2 = 64, blur annulus x2 = 96. About 1,376.
"""
import json
import math
import shutil
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a320_nacelle_geom as G  # noqa: E402
import a320_nacelle_tex as T  # noqa: E402
import a320_scene as S  # noqa: E402

GLB = S.ROOT / "game/aircraft/a320/models/exterior.glb"
PIVOTS = S.ROOT / "game/aircraft/a320/models/exterior_pivots.json"
BAK = Path("/tmp/exterior.glb.nacelle.bak")
TUBE_R = 0.025
PROUD = 0.030  # centreline forward of the measured paint, so the metal stands off it
LIP_MINOR = 8
HINGE_R = 0.015
HINGE_LEN = 0.08
HINGE_T = (0.32, 0.50, 0.68)
SPINNER_R = 0.18
BLUR_INNER = 0.11  # inside the spinner disc
PLANE_CLEAR = 0.012  # blur sits in the fan plane, just ahead of the blade faces
DOORS = (
    ("door_main_L", "MLGGearDoorL"), ("door_main_R", "MLGGearDoorR"),
    ("door_main_wing_L", "MLGWingDoorL2"), ("door_main_wing_R", "MLGWingDoorR2"),
    ("door_nose_L", "NLGForewardDoorL"), ("door_nose_R", "NLGForewardDoorR"),
    ("door_nose_aft_L", "NLGAftDoorL"), ("door_nose_aft_R", "NLGAftDoorR"),
)
FANS = (
    ("L", "fan_L", "FanLCFM56L", "detail_inlet_l", "detail_spinner_l", "detail_fan_blur_l"),
    ("R", "fan_R", "FanLCFM56R", "detail_inlet_r", "detail_spinner_r", "detail_fan_blur_r"),
)


def glb_json(path):
    data = Path(path).read_bytes()
    n = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20:20 + n])


def node_table(js):
    nodes, parent, out = js["nodes"], {}, {}
    for n in nodes:
        for c in n.get("children", []):
            parent[nodes[c]["name"]] = n.get("name")
    for n in nodes:
        out[n["name"]] = (n.get("translation"), n.get("rotation"), parent.get(n["name"]))
    return out


def q_deg(a, b):
    def nrm(q):
        q = q or [0, 0, 0, 1]
        L = math.sqrt(sum(x * x for x in q)) or 1.0
        return [x / L for x in q]
    a, b = nrm(a), nrm(b)
    return math.degrees(2 * math.acos(min(1.0, abs(sum(x * y for x, y in zip(a, b))))))


def vlen(a, b):
    a, b = a or [0, 0, 0], b or [0, 0, 0]
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def pivot_frame(name, spec):
    ob = bpy.data.objects["pivot_" + name]
    live = ob.matrix_world.translation.copy()
    p1, p2 = Vector(spec["p1"]), Vector(spec["p2"])
    forward = (ob.matrix_world.to_3x3() @ Vector((1.0, 0.0, 0.0))).normalized()
    want = (p2 - p1).normalized()
    ang = math.degrees(forward.angle(want))
    if (live - p1).length > 0.001 or ang > 0.1:
        print("PIVOT FRAME", name, "live", tuple(round(c, 4) for c in live), "json", spec["p1"], "deg", round(ang, 3))
        raise SystemExit(1)
    return live, forward, p1, p2


def median(xs):
    s = sorted(xs)
    return s[len(s) // 2]


def main():
    src = node_table(js := glb_json(GLB))
    mats_before = [m["name"] for m in js["materials"]]
    table = json.loads(PIVOTS.read_text())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    bpy.context.view_layer.update()
    if bpy.data.objects.get("detail_inlet_l"):
        print("NACELLE PRESENT, not adding again")
        return
    body = bpy.data.objects["body"]
    metal = bpy.data.materials.get("a320_plain_333")
    if metal is None:
        print("MISSING a320_plain_333")
        raise SystemExit(1)
    names = {o.name for o in bpy.data.objects}
    pivots = {o.name: o.matrix_world.copy() for o in bpy.data.objects if o.name.startswith("pivot_")}
    before = S.triangles()
    print("TRIANGLES", before)

    inlet_mat = T.principled("a320_inlet", (0.75, 0.76, 0.78), 0.22, 1.0)
    spin_mat = T.principled("a320_spinner", (1.0, 1.0, 1.0), 0.35, 0.4, T.procedural("a320_spinner_tex", 96, 96, T.spinner_px))
    blur_mat = T.blur_material(T.procedural("a320_fan_blur_tex", 128, 128, T.blur_px))
    static = body.parent

    for side, key, fan_name, inlet_name, spin_name, blur_name in FANS:
        centre, forward, _p1, _p2 = pivot_frame(key, table[key])
        fan = bpy.data.objects[fan_name]
        measured = G.measure_lip(body, centre, forward)
        if measured is None:
            print("INLET REJECT", side, "rim not closed")
            raise SystemExit(1)
        hits, rays = measured
        axials = [h[0] for h in hits]
        radii = [h[1] for h in hits]
        med_a, med_r = median(axials), median(radii)
        if not (0.6 < med_r < 1.3 and 0.35 < med_a < 1.4):
            print("INLET REJECT", side, "r", round(med_r, 3), "ahead", round(med_a, 3))
            raise SystemExit(1)
        ring = [h[2] + forward * PROUD for h in hits]
        lv, lf = G.tube(ring, TUBE_R, LIP_MINOR, forward)
        G.add_mesh(inlet_name, lv, lf, inlet_mat, static, smooth=True)
        tip, nose = G.fan_profile(fan, centre, forward)
        if not 0.5 < tip < 1.2:
            print("FAN REJECT", side, "tip", round(tip, 3))
            raise SystemExit(1)
        base = centre + forward * (nose + 0.02)
        sv, sf, su = G.spinner_mesh(base, forward, SPINNER_R)
        G.add_mesh(spin_name, sv, sf, spin_mat, fan, su, smooth=True)
        disc = centre + forward * PLANE_CLEAR
        bv, bf, bu = G.annulus(disc, forward, BLUR_INNER, tip)
        blur = G.add_mesh(blur_name, bv, bf, blur_mat, static, bu, shadows=False)
        if blur is not None and blur.parent == fan:
            print("BLUR PARENT", side)
            raise SystemExit(1)
        print("INLET", side, "ray", rays, "/", len(hits),
              "r", round(min(radii), 3), round(med_r, 3), round(max(radii), 3),
              "ahead", round(min(axials), 3), round(med_a, 3), round(max(axials), 3),
              "proud", PROUD, "tube", TUBE_R)
        print("FAN", side, "tip_r", round(tip, 3), "nose_ahead", round(nose, 3),
              "blur_inner", BLUR_INNER, "spinner_r", SPINNER_R, "parent", fan.name if spin_name in bpy.data.objects else "skip")

    for key, mesh_name in DOORS:
        _c, _f, p1, p2 = pivot_frame(key, table[key])
        door = bpy.data.objects[mesh_name]
        axis = (p2 - p1).normalized()
        for i, t in enumerate(HINGE_T):
            c = p1.lerp(p2, t)
            ends = G.cylinder(c - axis * (HINGE_LEN * 0.5), c + axis * (HINGE_LEN * 0.5), HINGE_R, 6)
            parent = door if i % 2 == 0 else body
            G.add_mesh("detail_hinge_%s_%d" % (key, i), *ends, metal, parent)

    after = S.triangles()
    delta = after - before
    new = sorted(o.name for o in bpy.data.objects if o.name.startswith("detail_inlet") or o.name.startswith("detail_hinge")
                 or o.name.startswith("detail_spinner") or o.name.startswith("detail_fan_blur"))
    print("TRIANGLES", after, "DELTA", delta)
    print("NEW OBJECTS", len(new), new)
    missing, bad = sorted(names - {o.name for o in bpy.data.objects}), []
    bpy.context.view_layer.update()
    for n, m in pivots.items():
        o = bpy.data.objects.get(n)
        dt = (o.matrix_world.translation - m.translation).length if o else 9
        ang = math.degrees(m.to_quaternion().rotation_difference(o.matrix_world.to_quaternion()).angle) if o else 9
        if o is None or dt > 0.001 or ang > 0.1:
            bad.append((n, round(dt, 5), round(ang, 4)))
    ok = not missing and not bad and delta <= 1500
    print("PIVOT ASSERT", "OK" if ok else "FAIL", "missing", missing, "moved", bad, "delta", delta)
    if not ok:
        raise SystemExit(1)
    shutil.copy2(GLB, BAK)
    S.export_glb(GLB)
    got = node_table(js2 := glb_json(GLB))
    gone = [k for k in src if k not in got]
    moved = [k for k, (t, r, par) in src.items()
             if k in got and (got[k][2] != par or vlen(t, got[k][0]) > 0.001 or q_deg(r, got[k][1]) > 0.1)]
    mats_after = [m["name"] for m in js2["materials"]]
    missing_mats = [m for m in mats_before if m not in mats_after]
    file_ok = not gone and not moved and not missing_mats
    print("EXPORT CHECK", "OK" if file_ok else "FAIL", "gone", gone, "moved", len(moved), "mats_missing", missing_mats)
    if not file_ok:
        shutil.copy2(BAK, GLB)
        raise SystemExit(1)


main()
