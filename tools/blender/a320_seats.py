"""Seats and cockpit door for interior.glb. Measure the deck, export via a320_scene.export_glb.
pivot_* stays within 1 mm / 0.1 deg or the glb is restored from /tmp/interior.glb.bak.
"""
import json
import math
import shutil
import struct
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/blender"))
import a320_scene as S  # noqa: E402

GLB = ROOT / "game/aircraft/a320/models/interior.glb"
BAK = Path("/tmp/interior.glb.bak")
PITCH, ROLL = 16.0, 20.0
def _glb(path):
    data, off = Path(path).read_bytes(), 12
    while off < len(data):
        ln, typ = struct.unpack_from("<II", data, off)
        chunk, off = data[off + 8:off + 8 + ln], off + 8 + ln
        if typ == 0x4E4F534A:
            return json.loads(chunk)
    raise RuntimeError("no glTF json")

def _file_pivots(path):
    names, piv = [], {}
    for n in _glb(path)["nodes"]:
        name = n.get("name", "")
        names.append(name)
        if name.startswith("pivot_"):
            piv[name] = (n.get("translation", [0, 0, 0]), n.get("rotation", [0, 0, 0, 1]))
    return names, piv

def _qdeg(a, b):
    return math.degrees(2 * math.acos(min(1.0, abs(sum(x * y for x, y in zip(a, b))))))

def _restore(msg):
    shutil.copy(BAK, GLB)
    print("PIVOT ASSERT FAIL", msg)
    print("RESTORED", GLB)
    sys.exit(1)

def _shell(bm, grid, thick):
    nx, ny = len(grid), len(grid[0])
    top = [[bm.verts.new(p) for p in col] for col in grid]
    bot = [[bm.verts.new(p - thick) for p in col] for col in grid]
    for i in range(nx - 1):
        for j in range(ny - 1):
            bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
            bm.faces.new((bot[i][j], bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j]))
    rims = [([top[i][0] for i in range(nx)], [bot[i][0] for i in range(nx)]),
            ([top[i][ny - 1] for i in range(nx)], [bot[i][ny - 1] for i in range(nx)]),
            ([top[0][j] for j in range(ny)], [bot[0][j] for j in range(ny)]),
            ([top[nx - 1][j] for j in range(ny)], [bot[nx - 1][j] for j in range(ny)])]
    for a, b in rims:
        for i in range(len(a) - 1):
            bm.faces.new((a[i], b[i], b[i + 1], a[i + 1]))

def _box(bm, x0, x1, y0, y1, z0, z1):
    _shell(bm, [[Vector((x, y, z1)) for y in (min(y0, y1), max(y0, y1))]
                for x in (min(x0, x1), max(x0, x1))], Vector((0, 0, abs(z1 - z0))))

def _ls(a, b, n):
    return [a + (b - a) * i / (n - 1) for i in range(n)]

def _finish(bm, name, mat, uv, smooth, root):
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.validate()
    me.materials.append(mat)
    me.uv_layers.new(name="UVMap")
    for d in me.uv_layers.active.data:
        d.uv = uv
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = root
    ob.matrix_world = Matrix.Identity(4)
    return ob

def _seat(y_in, y_out, x_front, floor, pan):
    bm, depth, rec = bmesh.new(), 0.44, math.radians(11)
    y0, y1 = sorted((y_in, y_out))
    x_rear, cy = x_front + depth, (y0 + y1) / 2
    xs, ys = _ls(x_front, x_rear, 7), _ls(y0, y1, 5)

    def pz(x, y):
        fx = 1 - abs((x - (x_front + x_rear) / 2) / (depth / 2))
        fy = 1 - abs((y - cy) / ((y1 - y0) / 2))
        return pan + 0.014 * fx * fy - 0.02 * max(0.0, 1 - (x - x_front) / 0.10)

    _shell(bm, [[Vector((x, y, pz(x, y))) for y in ys] for x in xs], Vector((0, 0, 0.09)))
    z0, z1 = pan - 0.01, pan + 0.66
    aft = Vector((-math.cos(rec), 0, math.sin(rec))) * 0.06  # shell subtracts thick; negate so the pad grows aft

    def bx(z, y, inset):
        t = (z - z0) / (z1 - z0)
        side = abs((y - cy) / ((y1 - y0) / 2))
        return x_rear - 0.02 + (z - z0) * math.tan(rec) - 0.012 * math.sin(math.pi * min(1, t / 0.55)) + 0.01 * side + inset

    zs = _ls(z0, z1, 6)
    _shell(bm, [[Vector((bx(z, y, 0), y, z)) for y in _ls(y0 + 0.01 * (z - z0) / (z1 - z0),
                                                          y1 - 0.01 * (z - z0) / (z1 - z0), 5)] for z in zs], aft)
    hz0 = z1 - 0.02
    _shell(bm, [[Vector((bx(z, y, -0.014 * abs(y - cy) / 0.11), y, z)) for y in _ls(cy - 0.11, cy + 0.11, 4)]
                for z in _ls(hz0, z1 + 0.18, 3)], aft * 0.9)
    _box(bm, x_front + 0.14, x_rear - 0.02, y0 - (0.02 if abs(y0) > abs(y1) else 0), y0 + 0.05, pan + 0.15, pan + 0.20)
    _box(bm, x_front + 0.14, x_rear - 0.02, y1 - 0.05, y1 + (0.02 if abs(y1) > abs(y0) else 0), pan + 0.15, pan + 0.20)
    _box(bm, x_front + 0.20, x_front + 0.25, y0 + 0.005, y0 + 0.04, pan - 0.01, pan + 0.15)
    _box(bm, x_front + 0.20, x_front + 0.25, y1 - 0.04, y1 - 0.005, pan - 0.01, pan + 0.15)
    _box(bm, x_front + 0.10, x_rear - 0.06, cy - 0.08, cy + 0.08, floor + 0.04, pan - 0.09)
    _box(bm, x_front + 0.06, x_rear - 0.03, cy - 0.12, cy + 0.12, floor, floor + 0.045)
    return bm

def _jump(floor, pan, x_nose, x_door):
    bm, y0, y1 = bmesh.new(), -0.16, 0.16
    xs = _ls(x_nose, x_door - 0.06, 5)

    def pz(x, y):
        return pan + 0.008 * (1 - abs(y) / 0.16) * (1 - abs((x - (xs[0] + xs[-1]) / 2) / (xs[-1] - xs[0])))

    _shell(bm, [[Vector((x, y, pz(x, y))) for y in _ls(y0, y1, 4)] for x in xs], Vector((0, 0, 0.055)))
    _shell(bm, [[Vector((x_door - 0.055, y, z)) for y in _ls(-0.145, 0.145, 4)] for z in _ls(pan, pan + 0.58, 4)],
           Vector((-0.04, 0, 0)))
    _shell(bm, [[Vector((x_door - 0.05, y, z)) for y in _ls(-0.09, 0.09, 3)] for z in _ls(pan + 0.52, pan + 0.70, 3)],
           Vector((-0.045, 0, 0)))
    for y in (-0.12, 0.12):
        _box(bm, x_nose + 0.02, x_nose + 0.055, y - 0.015, y + 0.015, floor, pan - 0.055)
        _box(bm, x_door - 0.06, x_door - 0.03, y - 0.018, y + 0.018, pan - 0.03, pan + 0.03)
    return bm

def _door(x, y0, y1, z0, z1, wy0, wy1, wz0, wz1):
    bm, parts = bmesh.new(), [(y0, wy0, z0, z1), (wy1, y1, z0, z1), (wy0, wy1, wz1, z1), (wy0, wy1, z0, wz0)]
    for a, b, c, d in parts:
        _box(bm, x, x + 0.028, a, b, c, d)
    for a, b in ((wy0 - 0.028, wy0), (wy1, wy1 + 0.028)):
        _box(bm, x - 0.012, x, a, b, z0, z1)
    m = 0.016
    for a, b, c, d in ((wy0, wy1, wz1, wz1 + m), (wy0, wy1, wz0 - m, wz0),
                       (wy0 - m, wy0, wz0, wz1), (wy1, wy1 + m, wz0, wz1)):
        _box(bm, x - 0.01, x, a, b, c, d)
    return bm

def _envelope(mesh, pitch, roll):
    origin = pitch.matrix_world.translation.copy()
    axes = [(o.matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized() for o in (pitch, roll)]
    verts = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    pts = []
    for pd in (0.0, PITCH, -PITCH):
        for rd in (0.0, ROLL, -ROLL):
            rot = Matrix.Rotation(math.radians(rd), 3, axes[1]) @ Matrix.Rotation(math.radians(pd), 3, axes[0])
            pts.extend(origin + rot @ (v - origin) for v in verts)
    return pts

def _bb(pts):
    return [(min(p[i] for p in pts), max(p[i] for p in pts)) for i in range(3)]

def _hits(pts, box):
    return sum(all(box[i][0] <= p[i] <= box[i][1] for i in range(3)) for p in pts)

def _measure(cock):
    mw, me = cock.matrix_world, cock.data
    mats = [m.name for m in me.materials]
    vmat = [""] * len(me.vertices)
    for poly in me.polygons:
        for i in poly.vertices:
            vmat[i] = mats[poly.material_index]
    pts, carpet, glare = [], [], []
    for v, name in zip(me.vertices, vmat):
        p = mw @ v.co
        pts.append(p)
        carpet.append(p) if name == "a320_carpet2" else glare.append(p) if name == "a320_fd_glare" else None
    floor = sorted(p.z for p in carpet)[int(len(carpet) * 0.9)]
    ped = [p for p in pts if abs(p.y) < 0.36 and floor + 0.08 < p.z < 0.05]
    half = sorted(abs(p.y) for p in ped)[int(len(ped) * 0.98)]
    center = [p for p in ped if abs(p.y) < 0.10]
    bins = {}
    for p in pts:
        if p.z < floor + 1.45:
            bins[round(p.x * 50)] = bins.get(round(p.x * 50), 0) + 1
    cut = max(k for k, n in bins.items() if n > 400) / 50.0
    rim = [p for p in pts if abs(p.x - cut) < 0.08 and floor + 0.05 < p.z < floor + 1.35]
    shade = [p for p in glare if p.z < 0.55]
    return dict(pts=pts, floor=floor, ped_half=half, ped_aft=max(p.x for p in center), ped_top=max(p.z for p in center),
                cut=cut, y0=min(p.y for p in rim), y1=max(p.y for p in rim),
                shade_aft=max(p.x for p in shade), glare_top=max(p.z for p in glare))

def _span(sign, ped_half, env):
    inner = sign * (ped_half + 0.045)
    side = [p.y for p in env if p.y * sign > 0.4]
    outer = sign * (min(abs(y) for y in side) - 0.04)
    if abs(outer) < abs(inner) + 0.30:
        outer = inner + sign * 0.30
    return inner, outer

def main():
    shutil.copy(GLB, BAK)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    drop = ("seat_captain", "seat_fo", "seat_jump", "deck_door", "deck_door_window")
    for o in [o for o in bpy.data.objects if o.name.split(".")[0] in drop]:
        bpy.data.objects.remove(o, do_unlink=True)
    names0 = {o.name for o in bpy.data.objects}
    piv0 = {o.name: tuple(x.copy() for x in o.matrix_local.decompose()[:2])
            for o in bpy.data.objects if o.name.startswith("pivot_")}
    before = S.triangles()
    cock = bpy.data.objects["cockpit"]
    m = _measure(cock)
    envs = {n: _envelope(bpy.data.objects[a], bpy.data.objects[b], bpy.data.objects[c]) for n, a, b, c in (
        ("seat_captain", "sidestick_1", "pivot_sidestick_cpt_pitch", "pivot_sidestick_cpt_roll"),
        ("seat_fo", "sidestick_2", "pivot_sidestick_fo_pitch", "pivot_sidestick_fo_roll"))}
    leather, glass = bpy.data.materials["a320_fd_leather"], bpy.data.materials["a320_glass"]
    door_mat = bpy.data.materials.get("a320_fd_main") or bpy.data.materials["a320_plain_333"]
    pan = m["floor"] + 0.33
    seats = []
    for name, sign in (("seat_captain", -1), ("seat_fo", 1)):
        env = envs[name]
        inner, outer = _span(sign, m["ped_half"], env)
        y0, y1 = sorted((inner, outer))
        reach = [p.x for p in env if y0 <= p.y <= y1]
        pivot_x = bpy.data.objects["pivot_sidestick_%s_pitch" % ("cpt" if sign < 0 else "fo")].matrix_world.translation.x
        front = pivot_x + 0.06
        if reach:
            front = max(front, max(reach) + 0.04)
        seats.append(_finish(_seat(inner, outer, front, m["floor"], pan), name, leather, (0.252, 0.138), True, cock))
    door_x = max(m["cut"] + 0.04, m["shade_aft"] + 0.03, m["ped_aft"] + 0.06)
    y0, y1, wy0, wy1 = m["y0"] + 0.015, m["y1"] - 0.015, -0.09, 0.09
    for _ in range(6):
        over = [p.z for p in m["pts"] if abs(p.x - door_x) < 0.08 and abs(p.y) < 0.55 and p.z > 0.90]
        top = min((min(over) - 0.025) if over else m["floor"] + 1.64, m["glare_top"] - 0.06)
        if _hits(m["pts"], [(door_x, door_x + 0.03), (y0, y1), (m["floor"] + 0.04, top - 0.02)]) < 25:
            break
        door_x += 0.015
    z0, wz1 = m["floor"] - 0.004, min(top - 0.18, m["floor"] + 1.40)
    wz0 = wz1 - 0.11
    door = _finish(_door(door_x, y0, y1, z0, top, wy0, wy1, wz0, wz1), "deck_door", door_mat, (0.352, 0.086), False, cock)
    win = bmesh.new()
    _box(win, door_x + 0.008, door_x + 0.014, wy0 + 0.01, wy1 - 0.01, wz0 + 0.01, wz1 - 0.01)
    window = _finish(win, "deck_door_window", glass, (0.352, 0.086), False, cock)
    depth = min(0.32, max(0.22, (door_x - 0.02) - m["ped_aft"] - 0.09))
    jump = _finish(_jump(m["floor"], pan - 0.02, door_x - 0.06 - depth, door_x - 0.015),
                   "seat_jump", leather, (0.252, 0.138), True, cock)
    built = seats + [jump, door, window]
    lost = sorted(n for n in names0 if bpy.data.objects.get(n) is None)
    moved = []
    for name, (loc, rot) in piv0.items():
        o = bpy.data.objects.get(name)
        if o is None:
            moved.append(name)
            continue
        loc2, rot2, _s = o.matrix_local.decompose()
        if (loc2 - loc).length > 0.001 or abs(rot.dot(rot2)) < math.cos(math.radians(0.05)):
            moved.append(name)
    bad_parent = [o.name for o in built if o.parent != cock]
    new_tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in built)
    if lost or moved or bad_parent or new_tris > 4000:
        _restore("lost %s moved %s parent %s tris %d" % (lost, moved, bad_parent, new_tris))
    for ob, env in ((seats[0], envs["seat_captain"]), (seats[1], envs["seat_fo"])):
        bb = _bb([ob.matrix_world @ Vector(c) for c in ob.bound_box])
        eb = _bb(env)
        if all(bb[i][0] <= eb[i][1] and eb[i][0] <= bb[i][1] for i in range(3)):
            _restore("%s intersects sidestick travel" % ob.name)
    after = S.triangles()
    print("MEASURE floor_z %.3f ped_half_y %.3f ped_aft_x %.3f ped_top_z %.3f cut_x %.3f rim_y %.3f..%.3f shade_aft %.3f glare_top %.3f" % (
        m["floor"], m["ped_half"], m["ped_aft"], m["ped_top"], m["cut"], m["y0"], m["y1"], m["shade_aft"], m["glare_top"]))
    for ob in built:
        bb = _bb([ob.matrix_world @ Vector(c) for c in ob.bound_box])
        print("PLACE %s x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f tris %d parent %s" % (
            ob.name, bb[0][0], bb[0][1], bb[1][0], bb[1][1], bb[2][0], bb[2][1],
            sum(len(p.vertices) - 2 for p in ob.data.polygons), ob.parent.name))
    print("TRIANGLES before %d after %d delta %d new %d" % (before, after, after - before, new_tris))
    print("PIVOT ASSERT scene ok pivots %d names %d" % (len(piv0), len(names0)))
    S.export_glb(GLB)
    nb, pb = _file_pivots(BAK)
    n1, p1 = _file_pivots(GLB)
    bad, worst = [n for n in nb if n not in set(n1)], [0.0, 0.0]
    for name, (t0, r0) in pb.items():
        if name not in p1:
            bad.append(name)
            continue
        dt, da = math.dist(t0, p1[name][0]), _qdeg(r0, p1[name][1])
        worst = [max(worst[0], dt), max(worst[1], da)]
        if dt > 0.001 or da > 0.1:
            bad.append(name)
    if bad:
        _restore("file %s" % bad[:8])
    print("PIVOT ASSERT file ok pivots %d worst %.4f mm %.4f deg" % (len(pb), worst[0] * 1000, worst[1]))

main()
