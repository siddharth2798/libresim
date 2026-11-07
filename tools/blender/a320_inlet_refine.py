"""Replace the A320 inlet lips with a rounder tube. The first nacelle pass is 20 by 8.

Blender -b --factory-startup --python tools/blender/a320_inlet_refine.py

Keeps every object name and every pivot_* transform. Restores exterior.glb if a node
moves. Added triangles for both lips stay under 2000.
"""
import json
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a320_nacelle_geom as G  # noqa: E402
import a320_scene as S  # noqa: E402

GLB = S.ROOT / "game/aircraft/a320/models/exterior.glb"
PIVOTS = S.ROOT / "game/aircraft/a320/models/exterior_pivots.json"
BAK = Path("/tmp/exterior.glb.inlet.bak")
MAJOR = 48
MINOR = 12
TUBE_R = 0.025
PROUD = 0.030
FANS = (("fan_L", "detail_inlet_l"), ("fan_R", "detail_inlet_r"))


def node_table(js):
    nodes, parent, out = js["nodes"], {}, {}
    for n in nodes:
        for c in n.get("children", []):
            parent[nodes[c]["name"]] = n.get("name")
    for n in nodes:
        out[n["name"]] = (n.get("translation"), n.get("rotation"), parent.get(n["name"]))
    return out


def glb_json(path):
    import struct
    with open(path, "rb") as f:
        f.read(12)
        n, _kind = struct.unpack("<I4s", f.read(8))
        return json.loads(f.read(n))


def q_deg(a, b):
    def nrm(q):
        q = q or [0, 0, 0, 1]
        length = math.sqrt(sum(x * x for x in q)) or 1.0
        return [x / length for x in q]
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
    if (live - p1).length > 0.001 or math.degrees(forward.angle(want)) > 0.1:
        raise SystemExit("pivot frame moved: %s" % name)
    return forward


def replace(ob, verts, faces):
    me = bpy.data.meshes.new(ob.name + "_fine")
    me.from_pydata(verts, [], faces)
    me.validate()
    for p in me.polygons:
        p.use_smooth = True
    if ob.data.materials:
        me.materials.append(ob.data.materials[0])
    old = ob.data
    ob.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)


def main():
    if not GLB.is_file():
        raise SystemExit("missing %s" % GLB)
    src = node_table(js := glb_json(GLB))
    mats_before = [m["name"] for m in js["materials"]]
    table = json.loads(PIVOTS.read_text())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    bpy.context.view_layer.update()
    if bpy.data.objects.get("detail_inlet_l") is None:
        print("NO INLET, skip")
        return
    body = bpy.data.objects["body"]
    names = {o.name for o in bpy.data.objects}
    pivots = {o.name: o.matrix_world.copy() for o in bpy.data.objects if o.name.startswith("pivot_")}
    before = S.triangles()
    for key, inlet_name in FANS:
        forward = pivot_frame(key, table[key])
        centre = bpy.data.objects["pivot_" + key].matrix_world.translation.copy()
        measured = G.measure_lip(body, centre, forward, MAJOR)
        if measured is None:
            raise SystemExit("lip not closed: %s" % key)
        hits, _rays = measured
        ring = [h[2] + forward * PROUD for h in hits]
        verts, faces = G.tube(ring, TUBE_R, MINOR, forward)
        replace(bpy.data.objects[inlet_name], verts, faces)
        print("LIP", inlet_name, "around", len(hits), "tube", MINOR)
    after = S.triangles()
    delta = after - before
    bpy.context.view_layer.update()
    missing, bad = sorted(names - {o.name for o in bpy.data.objects}), []
    for n, m in pivots.items():
        o = bpy.data.objects.get(n)
        dt = (o.matrix_world.translation - m.translation).length if o else 9
        ang = math.degrees(m.to_quaternion().rotation_difference(o.matrix_world.to_quaternion()).angle) if o else 9
        if o is None or dt > 0.001 or ang > 0.1:
            bad.append(n)
    if missing or bad or delta > 2000 or delta < 0:
        print("REFINE REJECT", "missing", missing, "moved", bad, "delta", delta)
        raise SystemExit(1)
    print("TRIANGLES", before, after, "DELTA", delta)
    shutil.copy2(GLB, BAK)
    S.export_glb(GLB)
    got = node_table(js2 := glb_json(GLB))
    gone = [k for k in src if k not in got]
    moved = [k for k, (t, r, par) in src.items()
             if k in got and (got[k][2] != par or vlen(t, got[k][0]) > 0.001 or q_deg(r, got[k][1]) > 0.1)]
    missing_mats = [m for m in mats_before if m not in [x["name"] for x in js2["materials"]]]
    if gone or moved or missing_mats:
        shutil.copy2(BAK, GLB)
        print("EXPORT REJECT", "gone", gone, "moved", len(moved), "mats", missing_mats)
        raise SystemExit(1)
    print("EXPORT CHECK OK")


if __name__ == "__main__":
    main()
