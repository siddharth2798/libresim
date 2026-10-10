"""Blender (4.x) headless: FlightGear c172p exterior (.ac, GPL-2.0-or-later, c172p team)
-> game/aircraft/c172/models/exterior.glb

Usage (repo root):
  blender -b --factory-startup --python tools/blender/convert_c172p.py
Needs data/raw/fg/c172p (sparse clone, see docs/FLIGHTGEAR_NOTES.md) and the AC3D
add-on in data/raw/fg/addon/Blender-AC3D-4.0.

Output frame = FlightGear model frame (x aft, y right, z up, origin = JSBSim VRP);
glTF export turns it Y-up. Animated parts are parented to empties named
"pivot_<part>" whose local +X is the hinge axis (from c172p.xml), so Godot can
rotate them about X. Normal maps (<tex>-normal.png) are wired into the materials.
"""
import importlib
import math
import sys
import types
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
FG = ROOT / "data/raw/fg/c172p/Models"
OUT = ROOT / "game/aircraft/c172/models"
sys.modules["imp"] = types.SimpleNamespace(reload=importlib.reload)  # add-on uses removed `imp`
sys.path.insert(0, str(ROOT / "data/raw/fg/addon/Blender-AC3D-4.0"))
import io_scene_ac3d  # noqa: E402

DROP = ["hotspots", "Propeller.Fast", "BeaconOffX", "courtesyon-l", "courtesyon-r",
        "sun_and_view_blocker", "PropellerCowlPlugs", "panel_blocker",
        # light halos / cones (free-sim's AircraftLights draws its own)
        "lightlanding", "lighttaxi", "landinglight", "taxilight", "LeftNavLight", "RightNavLight", "RearNavLight", "Beacon", "BeaconOff"]
# part -> (objects, hinge p1, hinge p2) in FG metres (c172p.xml rotate animations)
HINGES = {
    "aileron_L": (["leftaileron"], (0.862, -5.464, 0.459), (1.158, -2.616, 0.337)),
    "aileron_R": (["rightaileron"], (1.158, 2.616, 0.337), (0.862, 5.464, 0.459)),
    "elevator_L": (["elevatorleft"], (4.87869, -0.135, -0.42222), (4.7439, -1.7279, -0.4222)),
    "elevator_R": (["elevatorright"], (4.7439, 1.7279, -0.4222), (4.87869, 0.135, -0.42222)),
    "rudder": (["rudder_1", "ruddercablelefthinge", "ruddercablerighthinge"],
               (4.918, 0.0, -0.310), (5.805, -0.013, 1.007)),
    "flaps": (["flaps"], (1.152, -0.53, 0.32), (1.152, 0.47, 0.32)),
    "prop": (["Propeller", "Spinner"], (-1.96139, 0.00127, -0.0519), (-0.96139, 0.00127, -0.0519)),
}


def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    io_scene_ac3d.register()


def drop(name):
    o = bpy.data.objects.get(name)
    if o is None:
        return
    for c in list(o.children_recursive):
        bpy.data.objects.remove(c, do_unlink=True)
    bpy.data.objects.remove(o, do_unlink=True)


def bake_world():
    """Apply all parent transforms so every mesh sits in model coordinates."""
    for o in bpy.data.objects:
        o.select_set(True)
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for o in bpy.data.objects:
        if o.type == "EMPTY":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def add_pivot(name, objs, p1, p2):
    a, b = Vector(p1), Vector(p2)
    x = (b - a).normalized()
    up = Vector((0, 0, 1)) if abs(x.z) < 0.9 else Vector((1, 0, 0))
    y = up.cross(x).normalized()
    z = x.cross(y)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = a
    e = bpy.data.objects.new("pivot_" + name, None)
    e.matrix_world = m
    bpy.context.scene.collection.objects.link(e)
    for n in objs:
        o = bpy.data.objects.get(n)
        if o is None:
            print("WARN missing", n)
            continue
        mw = o.matrix_world.copy()
        o.parent = e
        o.matrix_world = mw


def wire_normal_maps():
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
        img = next((n for n in nodes if n.type == "TEX_IMAGE" and n.image), None)
        if bsdf is None:
            continue
        bsdf.inputs["Roughness"].default_value = 0.35
        bsdf.inputs["Metallic"].default_value = 0.0
        if img is None:
            continue
        stem = Path(img.image.filepath).stem
        nrm = Path(bpy.path.abspath(img.image.filepath)).with_name(stem + "-normal.png")
        if nrm.exists():
            t = nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(str(nrm))
            t.image.colorspace_settings.name = "Non-Color"
            nm = nodes.new("ShaderNodeNormalMap")
            links.new(t.outputs["Color"], nm.inputs["Color"])
            links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])


def main():
    clean()
    bpy.ops.import_scene.import_ac3d(filepath=str(FG / "c172-common.ac"))
    for n in DROP:
        drop(n)
    bake_world()
    for part, (objs, p1, p2) in HINGES.items():
        add_pivot(part, objs, p1, p2)
    wire_normal_maps()
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT / "exterior.glb"), export_format="GLB",
                              export_yup=True, export_apply=True, export_cameras=False,
                              export_lights=False, export_image_format="AUTO")
    print("EXPORTED", OUT / "exterior.glb", "objects", len(bpy.data.objects))


main()
