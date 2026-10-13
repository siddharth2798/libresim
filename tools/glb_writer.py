"""Minimal glTF 2.0 binary (.glb) writer: one mesh, one primitive per material.

Geometry is passed as numpy arrays in glTF axes (x = east, y = up, z = south), so the
game can load the file with GLTFDocument and place it directly. Materials only carry
a name and a base colour; the game swaps in its own shaders by material name
(world/terminals.gd), and Blender / any glTF viewer still shows sensible colours.
"""
import json
import struct

import numpy as np


class Glb:
    def __init__(self):
        self.prims = {}  # material name -> [positions list, normals list, indices list, count]
        self.colors = {}

    def add(self, material, pos, nrm, idx, color=(0.8, 0.8, 0.8)):
        """Append triangles: pos/nrm (n, 3) float, idx (m,) int (local to this call)."""
        if len(idx) == 0:
            return
        # one primitive per (material, colour): the colour rides in the name, "panel#e6dbbf"
        material = "%s#%02x%02x%02x" % (material, *[int(round(min(max(v, 0.0), 1.0) * 255)) for v in color[:3]])
        p = self.prims.setdefault(material, [[], [], [], 0])
        p[0].append(np.asarray(pos, np.float32))
        p[1].append(np.asarray(nrm, np.float32))
        p[2].append(np.asarray(idx, np.uint32) + p[3])
        p[3] += len(pos)
        self.colors.setdefault(material, color)

    def shift_y(self, dy):
        """Raise every vertex by dy(x, z) metres (callable on arrays): lets a model follow the
        ground under it. Call after all geometry is added."""
        for ps, *_ in self.prims.values():
            for i, a in enumerate(ps):
                ps[i] = a + np.asarray([0.0, 1.0, 0.0], np.float32) * np.asarray(dy(a[:, 0], a[:, 2]), np.float32)[:, None]

    def save(self, path):
        buf = bytearray()
        views, accs, prims, mats = [], [], [], []

        def view(data, target):
            while len(buf) % 4:
                buf.append(0)
            views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(data), "target": target})
            buf.extend(data)
            return len(views) - 1

        for name, (ps, ns, ix, _) in self.prims.items():
            pos = np.concatenate(ps)
            nrm = np.concatenate(ns)
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
            idx = np.concatenate(ix)
            a_pos = len(accs)
            accs.append({"bufferView": view(pos.tobytes(), 34962), "componentType": 5126, "count": len(pos),
                         "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()})
            accs.append({"bufferView": view(nrm.astype(np.float32).tobytes(), 34962), "componentType": 5126,
                         "count": len(nrm), "type": "VEC3"})
            accs.append({"bufferView": view(idx.tobytes(), 34963), "componentType": 5125, "count": len(idx),
                         "type": "SCALAR"})
            mats.append({"name": name, "pbrMetallicRoughness": {
                "baseColorFactor": list(self.colors[name]) + [1.0], "metallicFactor": 0.0, "roughnessFactor": 0.8},
                "doubleSided": True})
            prims.append({"attributes": {"POSITION": a_pos, "NORMAL": a_pos + 1}, "indices": a_pos + 2,
                          "material": len(mats) - 1})
        doc = {"asset": {"version": "2.0", "generator": "free-sim tools/glb_writer.py"},
               "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "terminal"}],
               "meshes": [{"primitives": prims}], "materials": mats, "accessors": accs,
               "bufferViews": views, "buffers": [{"byteLength": len(buf)}]}
        js = json.dumps(doc, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        buf += b"\0" * (-len(buf) % 4)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(buf)))
            f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            f.write(struct.pack("<II", len(buf), 0x004E4942) + bytes(buf))
