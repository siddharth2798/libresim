"""Blender helpers for the A320 conversion (run inside Blender: `blender -b --python ...`).

Builds Blender objects from the pure-Python AC3D parser (tools/blender/ac3d_parse.py), because Blender 5.x
has no AC3D importer. Frame of everything built here: FlightGear model frame (x aft, y right, z up) which is
also JSBSim's structural frame for this model (so the glb origin = structural origin, model.origin_m = 0);
glTF export turns it Y-up (aircraft_model.fg_transform places it).
Upstream: FlightGear A320-family (GPL-2.0-only), see third_party/a320-family/SOURCE.md for credits and changes.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/blender"))
import ac3d_parse as ac  # noqa: E402

TEX = ROOT / "data/processed/a320/tex"
_mats = {}
LENS = {"glass.red": (0.85, 0.05, 0.05), "glass.green": (0.05, 0.7, 0.1), "glass.white": (0.9, 0.9, 0.9)}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()


def _principled(name, rgb=(0.8, 0.8, 0.8), tex=None, rough=0.45, metal=0.0, alpha=1.0, blend=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if tex is not None:
        t = m.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(str(tex))
        t.image.alpha_mode = "STRAIGHT" if blend else "NONE"
        m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
        if blend:
            m.node_tree.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
    if blend or alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    m.use_backface_culling = False  # thin trailing edges / skins are single sided in the source
    return m


def material(texture, acmat, rgb):
    """Material for a face: by texture stem (tex/<stem>.png) when present, else by a coarse colour bucket."""
    name = acmat["name"] if acmat else ""
    stem = Path(texture).stem.lower().replace("-", "_") if texture else ""
    alias = {"fuse_main": "fuselage", "landinggears": "gear", "engine_cfm56": "engine"}
    stem = alias.get(stem, stem)
    key = None
    if texture == "wheel_mat":
        key = "a320_wheel_mat"
    elif name in LENS:
        key = "lens_" + name.split(".")[1]
    elif name.startswith("glass") or name.startswith("ecam_trans"):
        key = "a320_glass"
    elif stem and (TEX / (stem + ".png")).exists():
        key = "a320_" + stem
    else:
        q = tuple(round(c * 3) / 3 for c in rgb[:3])
        key = "a320_plain_%d%d%d" % tuple(int(c * 3) for c in q)
    if key in _mats:
        return _mats[key]
    if key.startswith("lens_"):
        m = _principled(key, LENS["glass." + key[5:]], rough=0.2)
    elif key == "a320_glass":
        m = _principled(key, (0.05, 0.07, 0.09), rough=0.04, alpha=0.3)
    elif key == "a320_wheel_mat":
        m = _principled("wheel_mat", tex=TEX / "gear.png", rough=0.7)
    elif key.startswith("a320_plain"):
        m = _principled(key, q, rough=0.6, metal=0.2 if sum(q) > 1 else 0.0)
    else:
        blend = key in ("a320_fd_glare",)
        m = _principled(key, tex=TEX / (stem + ".png"), rough=0.4 if key == "a320_fuselage" else 0.55,
                        metal=0.1 if key in ("a320_gear", "a320_engine") else 0.0, blend=blend)
    _mats[key] = m
    return m


def import_ac(path, keep, offset=(0, 0, 0), wheel_names=(), face_keep=None):
    """Create one Blender mesh object per AC3D poly with geometry; keep(name) filters. Returns {name: object}."""
    mats, root = ac.parse(str(path))
    out = {}
    for o, wv in ac.walk(root):
        if not keep(o.name):
            continue
        verts = [tuple(c + off for c, off in zip(ac.to_fg(v), offset)) for v in wv]
        faces, uvs, fmat, smooth = [], [], [], []
        slots = {}
        for flags, mi, refs in o.surfs:
            if flags & 0xF or len(refs) < 3:
                continue
            if face_keep is not None:
                cen = [sum(verts[r[0]][i] for r in refs) / len(refs) for i in range(3)]
                if not face_keep(o.name, cen):
                    continue
            acm = mats[mi] if mi < len(mats) else None
            m = material("wheel_mat" if o.name in wheel_names else o.texture, acm, acm["rgb"] if acm else (0.8, 0.8, 0.8))
            slot = slots.setdefault(m.name, len(slots))
            faces.append([r[0] for r in refs])
            uvs.append([(r[1] * o.texrep[0] + o.texoff[0], r[2] * o.texrep[1] + o.texoff[1]) for r in refs])
            fmat.append((slot, m))
            smooth.append(bool(flags & 0x10))
        if not faces:
            continue
        me = bpy.data.meshes.new(o.name)
        me.from_pydata(verts, [], faces)
        uv = me.uv_layers.new(name="UVMap")
        li = 0
        for f_uv in uvs:
            for u, v in f_uv:
                uv.data[li].uv = (u, v)
                li += 1
        for name in slots:
            me.materials.append(bpy.data.materials[name])
        for p, (slot, _) in zip(me.polygons, fmat):
            p.material_index = slot
        for p, s in zip(me.polygons, smooth):
            p.use_smooth = s
        me.validate(verbose=False)
        ob = bpy.data.objects.new(o.name, me)
        bpy.context.scene.collection.objects.link(ob)
        out[o.name] = ob
    return out


def add_pivot(name, objs, p1, p2, parent=None):
    """Empty pivot_<name> at p1, local +X along p1->p2; objs (objects or pivots) are parented keeping their place."""
    a, b = Vector(p1), Vector(p2)
    x = (b - a).normalized()
    up = Vector((0, 0, 1)) if abs(x.z) < 0.9 else Vector((1, 0, 0))
    y = up.cross(x).normalized()
    m = Matrix((x, y, x.cross(y))).transposed().to_4x4()
    m.translation = a
    e = bpy.data.objects.new("pivot_" + name, None)
    bpy.context.scene.collection.objects.link(e)
    e.matrix_world = m
    if parent is not None:
        e.parent = parent
        e.matrix_world = m
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = e
        o.matrix_world = mw
    return e


def join_static(objs, name):
    """Join free (unparented) mesh objects into one named mesh."""
    objs = [o for o in objs if o.parent is None and o.type == "MESH"]
    if not objs:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    j = bpy.context.view_layer.objects.active
    j.name = name
    j.data.name = name
    return j


def smooth_by_angle(deg=40.0):
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(deg))


def triangles():
    n = 0
    for o in bpy.data.objects:
        if o.type == "MESH":
            n += sum(max(len(p.vertices) - 2, 0) for p in o.data.polygons)
    return n


def export_glb(path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_yup=True, export_apply=True,
                              export_cameras=False, export_lights=False, export_image_format="AUTO",
                              export_copyright="GPL-2.0-only; derived from FlightGear A320-family (see third_party/a320-family/SOURCE.md)")


def bbox(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    return [(min(p[i] for p in pts), max(p[i] for p in pts)) for i in range(3)]
