"""Blender headless: build free-sim's own ground-service vehicles (GPL-2.0-or-later, free-sim).
  blender -b --factory-startup --python tools/blender/make_ground_vehicles.py
Writes game/world/models/vehicles/{fuel_truck,gpu,baggage_tug,baggage_cart,follow_me}.glb.
Convention: metres, origin on the ground at the vehicle centre, front toward +Y in Blender
(-Z in Godot after glTF export), z up.
"""
import math
from pathlib import Path

import bpy

OUT = Path(__file__).resolve().parents[2] / "game/world/models/vehicles"


def mat(name, rgb, metal=0.0, rough=0.5):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m


def box(name, size, loc, m):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    o.data.materials.append(m)
    return o


def cyl(name, r, depth, loc, rot, m, verts=24):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(m)
    return o


def wheels(xs, ys, r, width, rubber, hub):
    for x in xs:
        for y in ys:
            cyl("wheel", r, width, (x, y, r), (0, math.pi / 2, 0), rubber)
            cyl("hub", r * 0.5, width * 1.05, (x, y, r), (0, math.pi / 2, 0), hub, 12)


def text(s, loc, rot, size, m):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    t = bpy.context.object
    t.data.body = s
    t.data.size = size
    t.data.align_x = "CENTER"
    t.data.extrude = 0.01
    t.data.materials.append(m)
    bpy.ops.object.convert(target="MESH")
    return t


def export(name):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT / f"{name}.glb"), export_format="GLB", export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False)
    print("EXPORTED", name)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def common():
    return (mat("rubber", (0.03, 0.03, 0.03), rough=0.9), mat("hub", (0.6, 0.6, 0.62), metal=0.8, rough=0.3),
            mat("glass", (0.08, 0.12, 0.16), metal=0.2, rough=0.05), mat("chassis", (0.12, 0.12, 0.13), rough=0.7))


def fuel_truck():
    reset()
    rubber, hub, glass, chassis = common()
    white = mat("white", (0.9, 0.9, 0.88), rough=0.35)
    red = mat("red", (0.75, 0.08, 0.06), rough=0.4)
    box("chassis", (2.3, 7.8, 0.35), (0, 0, 0.75), chassis)
    box("cab", (2.4, 2.1, 1.9), (0, 2.75, 1.85), white)
    box("windscreen", (2.2, 0.05, 0.8), (0, 3.81, 2.25), glass)
    for s in (-1, 1):
        box("side_window", (0.05, 1.0, 0.65), (s * 1.21, 3.0, 2.25), glass)
    cyl("tank", 1.05, 5.0, (0, -1.15, 2.0), (math.pi / 2, 0, 0), white, 32)
    cyl("band", 1.07, 0.5, (0, -1.15, 2.0), (math.pi / 2, 0, 0), red, 32)
    cyl("hose_reel", 0.35, 0.6, (0, -3.75, 1.3), (0, math.pi / 2, 0), red)
    text("AVGAS 100LL", (1.1, -1.15, 2.0), (math.pi / 2, 0, math.pi / 2), 0.38, red)
    wheels((-1.0, 1.0), (2.6, -1.6, -2.9), 0.5, 0.35, rubber, hub)
    export("fuel_truck")


def gpu():
    reset()
    rubber, hub, glass, chassis = common()
    yellow = mat("yellow", (0.95, 0.72, 0.08), rough=0.45)
    box("body", (1.2, 1.9, 1.1), (0, 0, 0.95), yellow)
    box("panel", (0.02, 0.8, 0.5), (0.61, 0.2, 1.05), chassis)
    box("towbar", (0.08, 1.0, 0.08), (0, 1.4, 0.45), chassis)
    cyl("cable", 0.04, 3.0, (0.3, 1.0, 0.9), (math.pi / 2, 0.3, 0), chassis, 8)
    text("GPU 28V", (0.62, 0.0, 1.3), (math.pi / 2, 0, math.pi / 2), 0.22, chassis)
    wheels((-0.55, 0.55), (0.65, -0.65), 0.25, 0.18, rubber, hub)
    export("gpu")


def baggage_tug():
    reset()
    rubber, hub, glass, chassis = common()
    blue = mat("blue", (0.1, 0.3, 0.65), rough=0.45)
    box("body", (1.4, 2.6, 0.7), (0, 0, 0.75), blue)
    box("seat", (0.6, 0.5, 0.5), (0, -0.2, 1.3), chassis)
    for x in (-0.65, 0.65):
        for y in (-0.6, 0.5):
            box("roof_post", (0.06, 0.06, 1.0), (x, y, 1.6), chassis)
    box("roof", (1.4, 1.3, 0.06), (0, -0.05, 2.12), blue)
    wheels((-0.62, 0.62), (0.85, -0.85), 0.3, 0.22, rubber, hub)
    export("baggage_tug")


def baggage_cart():
    reset()
    rubber, hub, glass, chassis = common()
    grey = mat("grey", (0.55, 0.57, 0.6), metal=0.5, rough=0.4)
    canvas = mat("canvas", (0.15, 0.32, 0.6), rough=0.8)
    box("bed", (1.5, 3.0, 0.12), (0, 0, 0.62), grey)
    for y in (-1.45, 0, 1.45):
        box("arch", (1.5, 0.06, 0.06), (0, y, 1.9), grey)
        for x in (-0.73, 0.73):
            box("post", (0.05, 0.05, 1.25), (x, y, 1.27), grey)
    box("canopy", (1.55, 3.0, 0.04), (0, 0, 1.95), canvas)
    box("bags", (1.2, 2.4, 0.6), (0, 0, 0.98), mat("bags", (0.35, 0.22, 0.12), rough=0.9))
    box("drawbar", (0.06, 1.2, 0.06), (0, 2.0, 0.4), chassis)
    wheels((-0.62, 0.62), (1.1, -1.1), 0.22, 0.15, rubber, hub)
    export("baggage_cart")


def follow_me():
    reset()
    rubber, hub, glass, chassis = common()
    yellow = mat("yellow", (0.98, 0.8, 0.05), rough=0.35)
    black = mat("black", (0.02, 0.02, 0.02), rough=0.4)
    box("body", (1.8, 4.4, 0.75), (0, 0, 0.75), yellow)
    box("cabin", (1.65, 2.2, 0.6), (0, -0.3, 1.42), yellow)
    box("windows", (1.67, 2.0, 0.42), (0, -0.3, 1.45), glass)
    box("sign", (1.4, 0.06, 0.5), (0, -1.3, 2.05), black)
    text("FOLLOW ME", (0, -1.34, 1.95), (math.pi / 2, 0, math.pi), 0.24, yellow)
    box("beacon", (0.3, 0.3, 0.15), (0, -0.3, 1.82), mat("amber", (1.0, 0.55, 0.05), rough=0.2))
    wheels((-0.8, 0.8), (1.4, -1.4), 0.33, 0.22, rubber, hub)
    export("follow_me")


fuel_truck()
gpu()
baggage_tug()
baggage_cart()
follow_me()
