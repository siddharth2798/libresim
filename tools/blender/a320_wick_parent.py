"""Parent static wicks to the surface they sit on, so they move with the flap, aileron, elevator or rudder.

Blender -b --factory-startup --python tools/blender/a320_wick_parent.py
Sharklet wicks stay on the wing. A tail wick that is not already on a host is moved onto the
trailing edge at its own span and parented. Flap, aileron and already-parented wicks stay as they
are. Restores the glb if a pivot_* moves.
"""
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a320_scene as S  # noqa: E402

GLB = S.ROOT / "game/aircraft/a320/models/exterior.glb"
BAK = Path("/tmp/exterior.glb.wick.bak")
WING = ("FlapL2", "FlapR2", "AileronL", "AileronR")
TAIL = ("ElevatorL", "ElevatorR", "Rudder")
HOSTS = WING + TAIL


def world_verts(ob):
    mw = ob.matrix_world
    return [mw @ v.co for v in ob.data.vertices]


def nearest(point, names, clouds):
    best, vert, dist = None, None, 1e9
    for n in names:
        for v in clouds[n]:
            d = (point - v).length
            if d < dist:
                best, vert, dist = n, v, d
    return best, vert, dist


def rod_root(pts):
    # Aft is +X, so the root of the rod is the forward end, not the free tip.
    x0 = min(p.x for p in pts)
    near = [p for p in pts if p.x <= x0 + 0.004]
    return sum(near, Vector()) / len(near)


def section_te(ob, target, axis):
    key = (lambda v: v.y) if axis == "y" else (lambda v: v.z)
    mw = ob.matrix_world
    vs = [mw @ v.co for v in ob.data.vertices]
    best = None
    for e in ob.data.edges:
        a, b = vs[e.vertices[0]], vs[e.vertices[1]]
        den = key(b) - key(a)
        if not den or (key(a) - target) * (key(b) - target) > 0:
            continue
        p = a.lerp(b, (target - key(a)) / den)
        if best is None or p.x > best.x:
            best = p
    return best


def main():
    shutil.copy2(GLB, BAK)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    pivots = {o.name: o.matrix_world.copy() for o in bpy.data.objects if o.name.startswith("pivot_")}
    clouds = {n: world_verts(bpy.data.objects[n]) for n in HOSTS}
    for ob in list(bpy.data.objects):
        if not ob.name.startswith("detail_wick_"):
            continue
        if ob.parent and ob.parent.name in HOSTS:
            continue
        pts = world_verts(ob)
        base = sum(pts, Vector()) / len(pts)
        if abs(base.y) > 16.0:
            best, _vert, dist = nearest(base, HOSTS, clouds)
            print("WICK STAYS", ob.name, "y", round(base.y, 2), "nearest", best, round(dist, 3))
            continue
        if base.x > 10.0 and abs(base.y) <= 16.0:
            best, vert, dist = nearest(base, TAIL, clouds)
            root = rod_root(pts)
            axis = "z" if best == "Rudder" else "y"
            target = root.z if axis == "z" else root.y
            # End clusters leave the mid-span empty, so the nearest vertex is the wrong station.
            # The trailing edge there is the aft-most cross-section of the skin.
            te = section_te(bpy.data.objects[best], target, axis)
            if te is None:
                band = [v for v in clouds[best] if (v - vert).length <= 0.45]
                te = max(band, key=lambda v: v.x) if band else None
            gap = (te - root).length if te is not None else 1e9
            if te is None or (dist > 1.6 and gap > 1.6):
                print("WICK STAYS", ob.name, "y", round(base.y, 2), "nearest", best, round(dist, 3))
                continue
            mw = ob.matrix_world.copy()
            mw.translation = mw.translation + (Vector((te.x + 0.008, te.y, te.z)) - root)
            ob.matrix_world = mw
            ob.parent = bpy.data.objects[best]
            ob.matrix_world = mw
            print("WICK SNAPPED", ob.name, best, round(gap, 3))
            continue
        best, _vert, dist = nearest(base, WING, clouds)
        if dist > 0.8:
            print("WICK STAYS", ob.name, "y", round(base.y, 2), "nearest", best, round(dist, 3))
            continue
        mw = ob.matrix_world.copy()
        ob.parent = bpy.data.objects[best]
        ob.matrix_world = mw
    bad = []
    for n, m in pivots.items():
        o = bpy.data.objects[n]
        dt = (o.matrix_world.translation - m.translation).length
        ang = math.degrees(m.to_quaternion().rotation_difference(o.matrix_world.to_quaternion()).angle)
        if dt > 0.001 or ang > 0.1:
            bad.append(n)
    if bad:
        print("PIVOT ASSERT FAIL", bad)
        shutil.copy2(BAK, GLB)
        raise SystemExit(1)
    S.export_glb(GLB)
    print("EXPORTED", GLB)


main()
