"""Spinner swirl and fan-blur disc images, and the inlet / spinner / blur materials."""
import array
import math

import bpy


def procedural(name, w, h, fn):
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.alpha_mode = "STRAIGHT"
    img.file_format = "PNG"
    buf = array.array("f", [0.0]) * (w * h * 4)
    for y in range(h):
        for x in range(w):
            r, g, b, a = fn(x, y, w, h)
            i = (y * w + x) * 4
            buf[i:i + 4] = array.array("f", (r, g, b, a))
    img.pixels.foreach_set(buf)
    img.pack()
    return img


def _polar(x, y, w, h):
    du = (x + 0.5) / w - 0.5
    dv = (y + 0.5) / h - 0.5
    return math.hypot(du, dv) * 2.0, math.atan2(dv, du)


def spinner_px(x, y, w, h):
    r, ang = _polar(x, y, w, h)
    if r > 1.02:
        return (0.16, 0.17, 0.18, 1.0)
    # Two plain white arms. No lettering and no operator mark.
    if math.sin(ang * 2.0 - r * 8.0) > 0.65:
        return (0.93, 0.93, 0.91, 1.0)
    shade = 0.20 + 0.04 * (1.0 - min(r, 1.0))
    return (shade, shade + 0.01, shade + 0.02, 1.0)


def blur_px(x, y, w, h):
    r, ang = _polar(x, y, w, h)
    if r < 0.22 or r > 0.98:
        return (0.55, 0.56, 0.58, 0.0)
    fade = 1.0
    if r < 0.38:
        fade = (r - 0.22) / 0.16
    elif r > 0.84:
        fade = (0.98 - r) / 0.14
    wave = 0.5 + 0.5 * math.cos(ang * 12.0)
    grey = 0.40 + 0.30 * wave
    return (grey, grey, grey + 0.01, fade * (0.20 + 0.80 * wave))


def principled(name, rgb, rough, metal, tex=None, alpha=1.0, blend=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if tex is not None:
        t = m.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = tex
        m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
        if blend:
            # Constant factor exports as baseColorFactor.a (starts low). The texture alpha is the mask.
            mul = m.node_tree.nodes.new("ShaderNodeMath")
            mul.operation = "MULTIPLY"
            mul.inputs[0].default_value = alpha
            m.node_tree.links.new(t.outputs["Alpha"], mul.inputs[1])
            m.node_tree.links.new(mul.outputs["Value"], b.inputs["Alpha"])
    if blend or alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
        if hasattr(m, "blend_method"):
            m.blend_method = "BLEND"
    m.use_backface_culling = False
    return m


def blur_material(tex):
    m = principled("a320_fan_blur", (1.0, 1.0, 1.0), 0.6, 0.0, tex, alpha=0.05, blend=True)
    # Blender 5 calls the old show_transparent_back switch use_transparency_overlap.
    if hasattr(m, "show_transparent_back"):
        m.show_transparent_back = True
    if hasattr(m, "use_transparency_overlap"):
        m.use_transparency_overlap = True
    if hasattr(m, "shadow_method"):
        m.shadow_method = "NONE"
    return m
