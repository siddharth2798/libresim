"""UV2 and an occlusion map for the A320 glbs. Blender -b --factory-startup --python tools/blender/a320_bake.py
UVMap stays. A second UV with no triangle area is rebuilt. Occlusion is ray-cast (a320_ao_rays.py): Cycles' AO
bake writes an empty image in this Blender. Failure restores /tmp/<name>.glb.bake.bak.
"""
import json
import math
import shutil
import struct
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a320_scene as S  # noqa: E402

SKIP_MATS = {"a320_glass", "a320_screen", "wheel_mat", "a320_fan_blur"}


def _keep(name):
    return bool(name) and name not in SKIP_MATS and not name.startswith("lens_")


def _json(path):
    data = Path(path).read_bytes()
    n = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20:20 + n])


def _pivots(js):
    out = {}
    for n in js.get("nodes", []):
        if n.get("name", "").startswith("pivot_"):
            out[n["name"]] = (n.get("translation"), n.get("rotation"))
    return out


def _qdeg(a, b):
    def nrm(q):
        q = list(q or [0, 0, 0, 1])
        length = math.sqrt(sum(x * x for x in q)) or 1.0
        return [x / length for x in q]
    a, b = nrm(a), nrm(b)
    return math.degrees(2 * math.acos(min(1.0, abs(sum(x * y for x, y in zip(a, b))))))


def _vlen(a, b):
    a, b = a or [0, 0, 0], b or [0, 0, 0]
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def _targets():
    """Opaque meshes, one object per datablock. Fan blur is out; nacelle details stay."""
    out, seen = [], set()
    for o in bpy.data.objects:
        me = o.data if o.type == "MESH" else None
        if me is None or not me.polygons or o.name.startswith("detail_fan_blur_"):
            continue
        if not any(_keep(m.name if m else "") for m in me.materials):
            continue
        if me.as_pointer() in seen:
            continue
        seen.add(me.as_pointer())
        out.append(o)
    return out


def _first_uv(me):
    return next((layer for layer in me.uv_layers if layer.name != "UV2"), None)


def _uv_area(ob):
    """True when the second UV layer has triangles, not one point per face."""
    me = ob.data
    if len(me.uv_layers) < 2:
        return False
    uv, good, seen = me.uv_layers[1], 0, 0
    step = max(1, len(me.polygons) // 40)
    for i in range(0, len(me.polygons), step):
        if seen >= 40:
            break
        p = me.polygons[i]
        if len(p.loop_indices) < 3:
            continue
        pts = [(uv.data[li].uv.x, uv.data[li].uv.y) for li in p.loop_indices]
        ax, ay = pts[0]
        bx, by, cx, cy = pts[1][0], pts[1][1], pts[2][0], pts[2][1]
        seen += 1
        if abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) > 1e-8:
            good += 1
    return seen > 0 and good >= max(1, seen // 5)


def _sig(me):
    layer = _first_uv(me)
    if layer is None:
        return None
    n, step = len(layer.data), max(1, len(layer.data) // 32)
    vals = [layer.name, n]
    for i in range(0, n, step):
        uv = layer.data[i].uv
        vals.extend((round(float(uv.x), 5), round(float(uv.y), 5)))
    return tuple(vals)


def _unwrap(ob):
    """One object in edit mode. A multi-object project wrote a single point per face."""
    me = ob.data
    while len(me.uv_layers) > 1:
        me.uv_layers.remove(me.uv_layers[-1])
    if len(me.uv_layers) == 0:
        me.uv_layers.new(name="UVMap")
    me.uv_layers.new(name="UV2")
    me.uv_layers.active = me.uv_layers["UV2"]
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    result = bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.001)
    bpy.ops.object.mode_set(mode="OBJECT")
    if "FINISHED" not in set(result):
        raise RuntimeError("smart_project %s %s" % (ob.name, result))
    me.uv_layers[0].active_render = True


def _atlas(obs):
    """The largest mesh keeps most of the sheet. The rest share a side column."""
    ranked = sorted(obs, key=lambda o: (-len(o.data.polygons), o.name))
    _fit(ranked[0], 0.0, 0.0, 0.68, 1.0)
    rest = [(len(o.data.polygons), o) for o in ranked[1:]]
    total = sum(n for n, _o in rest) or 1
    heights = [max(0.004, n / total) for n, _o in rest]
    scale = 0.98 / sum(heights)
    y = 0.0
    for h, (_n, ob) in zip(heights, rest):
        _fit(ob, 0.70, y, 0.28, h * scale)
        y += h * scale


def _fit(ob, ox, oy, sx, sy):
    for el in ob.data.uv_layers[1].data:
        el.uv = (ox + el.uv.x * sx, oy + el.uv.y * sy)


def _bake(obs, png, dist):
    import a320_ao_rays as rays
    mean = rays.bake(obs, png, _keep, dist)
    if mean < 0.05:
        png.unlink(missing_ok=True)
        raise RuntimeError("ao bake mean %s" % round(mean, 3))


def _fail(bak, glb, msg):
    if bak.exists():
        shutil.copy2(bak, glb)
    print("BAKE FAIL", glb.name, msg)
    raise SystemExit(1)


def _file_uv2(js, mesh_name):
    meshes = js.get("meshes", [])
    for n in js.get("nodes", []):
        if n.get("name") == mesh_name and "mesh" in n:
            return any("TEXCOORD_1" in p.get("attributes", {}) for p in meshes[n["mesh"]].get("primitives", []))
    return False


def _print_uv(main_mesh, has):
    print("TRIANGLES", S.triangles())
    print("TEXCOORD", "TEXCOORD_0+TEXCOORD_1" if has else "TEXCOORD_0", main_mesh)


def _check_export(bak, glb, main_mesh):
    src, got = _json(bak), _json(glb)
    names = {n.get("name", "") for n in got.get("nodes", [])}
    gone = [n.get("name", "") for n in src.get("nodes", []) if n.get("name", "") not in names]
    after = _pivots(got)
    bad = [k for k, (loc, rot) in _pivots(src).items()
           if k not in after or _vlen(loc, after[k][0]) > 0.001 or _qdeg(rot, after[k][1]) > 0.1]
    ao_hit = [im.get("name", "") for im in got.get("images", []) if "ao_bake" in im.get("name", "").lower() or im.get("name") == "ao_skip"]
    has = _file_uv2(got, main_mesh)
    if gone or bad or ao_hit or not has:
        _fail(bak, glb, "gone %s moved %s ao_images %s uv2 %s" % (gone[:8], bad[:8], ao_hit, has))
    print("EXPORT CHECK OK pivots", len(after), "gone", 0)
    _print_uv(main_mesh, has)


def _run(glb, bak, main_mesh, dist):
    png = glb.with_name(glb.stem + "_ao.png")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    obs = _targets()
    if not obs:
        _fail(bak, glb, "no meshes to bake")
    # A black png from a failed save is small. A real map is rebuilt with its UV2.
    if png.exists() and png.stat().st_size > 100000 and all(_uv_area(o) for o in obs):
        print("AO SKIP", png.name, "UV2 present")
        _print_uv(main_mesh, True)
        return
    before = {o.data.as_pointer(): _sig(o.data) for o in obs}
    meshes = []
    for o in obs:
        if o.data not in meshes:
            meshes.append(o)
    print("UNWRAP", len(meshes))
    for o in meshes:
        _unwrap(o)
    bad = [o.name for o in meshes if not _uv_area(o)]
    if bad:
        _fail(bak, glb, "uv2 still has no triangle area %s" % bad[:6])
    _atlas(meshes)
    moved = [o.name for o in obs if _sig(o.data) != before.get(o.data.as_pointer())]
    if moved:
        _fail(bak, glb, "UVMap changed on %s" % moved[:4])
    _bake(obs, png, dist)
    S.export_glb(glb)
    _check_export(bak, glb, main_mesh)


def _one(glb, main_mesh, dist):
    bak = Path("/tmp") / ("%s.glb.bake.bak" % glb.stem)
    shutil.copy2(glb, bak)
    try:
        _run(glb, bak, main_mesh, dist)
    except SystemExit:
        raise
    except Exception as exc:
        shutil.copy2(bak, glb)
        print("BAKE FAIL", glb.name, exc)
        raise


def main():
    models = S.ROOT / "game/aircraft/a320/models"
    _one(models / "exterior.glb", "body", 2.0)
    _one(models / "interior.glb", "cockpit", 0.4)


main()
