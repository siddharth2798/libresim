"""Blender (4.x) headless: FlightGear c172p cockpit interior (GPL-2.0-or-later, c172p team)
-> game/aircraft/c172/models/interior.glb

Usage (repo root): blender -b --factory-startup --python tools/blender/convert_c172p_interior.py
Same frame as exterior.glb (FlightGear model frame, origin = JSBSim VRP). Includes the
panel shell, seats, levers and switches (c172p-interior.ac), both yokes and pilot
pedals. Instrument faces are NOT imported: free-sim draws live gauges at the real
instrument positions instead. Pivots: pivot_yoke_L / pivot_yoke_R (roll axis = +X;
the whole yoke also slides along X for pitch), pivot_throttle, pivot_mixture.
"""
import importlib
import re
import shutil
import sys
import types
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
FG = ROOT / "data/raw/fg/c172p/Models"
OUT = ROOT / "game/aircraft/c172/models"
sys.modules["imp"] = types.SimpleNamespace(reload=importlib.reload)
sys.path.insert(0, str(ROOT / "data/raw/fg/addon/Blender-AC3D-4.0"))
import io_scene_ac3d  # noqa: E402

PARTS = [  # (file, offset in FG metres)
    ("Interior/Panel/c172p-panel/c172p-interior.ac", (0, 0, 0)),
    ("Interior/Yoke/yoke.ac", (0, 0, 0)),
    ("Interior/Pedals/pedals.ac", (-0.56, -0.24, -0.61)),
    ("Interior/Pedals/pedals.ac", (-0.56, 0.24, -0.61)),
]
DROP_PREFIX = ("DomeLight", "glass_panel", "wing", "LowVoltageLed")
PIVOTS = {  # name -> (objects, point, axis)
    "yoke_L": (["LeftYoke", "LeftYokeMain"], (-0.34713, -0.22065, -0.09786), (1, 0, 0)),
    "yoke_R": (["RightYoke", "RightYokeMain"], (-0.34602, 0.23951, -0.09581), (1, 0, 0)),
    "throttle": (["Throttle"], None, (1, 0, 0)),
    "mixture": (["Mixture"], None, (1, 0, 0)),
}


def import_part(rel, off):
    before = set(bpy.data.objects)
    src = FG / rel
    # the AC3D importer only looks for textures beside the .ac; FlightGear uses a
    # texture-path, so import a copy placed in Models/ next to interior.png etc.
    if not all((src.parent / t).exists() for t in textures(src)):
        tmp = FG / ("_tmp_" + src.name)
        shutil.copy(src, tmp)
        src = tmp
    bpy.ops.import_scene.import_ac3d(filepath=str(src))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.location += Vector(off)


def textures(ac):
    return set(re.findall(r'^texture "([^"]+)"', ac.read_text(errors="ignore"), re.M))


def bake_world():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for o in list(bpy.data.objects):
        if o.type != "MESH" or o.name.startswith(DROP_PREFIX):
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def centre(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return sum(pts, Vector()) / 8


def add_pivot(name, objs, point, axis):
    found = [bpy.data.objects.get(n) for n in objs]
    found = [o for o in found if o]
    if not found:
        print("WARN no objects for", name)
        return
    p = Vector(point) if point else centre(found[0])
    x = Vector(axis).normalized()
    up = Vector((0, 0, 1)) if abs(x.z) < 0.9 else Vector((1, 0, 0))
    y = up.cross(x).normalized()
    m = Matrix((x, y, x.cross(y))).transposed().to_4x4()
    m.translation = p
    e = bpy.data.objects.new("pivot_" + name, None)
    e.matrix_world = m
    bpy.context.scene.collection.objects.link(e)
    for o in found:
        mw = o.matrix_world.copy()
        o.parent = e
        o.matrix_world = mw


def relink_images():
    """FlightGear finds textures via <texture-path>; point missing images at Models/."""
    for img in bpy.data.images:
        path = Path(bpy.path.abspath(img.filepath))
        if img.filepath and not path.exists():
            hits = list(FG.rglob(path.name))
            if hits:
                img.filepath = str(hits[0])
                img.reload()
            else:
                print("WARN texture not found", path.name)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    io_scene_ac3d.register()
    for rel, off in PARTS:
        import_part(rel, off)
    relink_images()
    bake_world()
    for n, (objs, pt, ax) in PIVOTS.items():
        add_pivot(n, objs, pt, ax)
    for mat in bpy.data.materials:
        b = mat.node_tree.nodes.get("Principled BSDF") if mat.use_nodes else None
        if b:
            b.inputs["Roughness"].default_value = 0.6
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT / "interior.glb"), export_format="GLB", export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False)
    print("EXPORTED", OUT / "interior.glb", "objects", len(bpy.data.objects))


main()
