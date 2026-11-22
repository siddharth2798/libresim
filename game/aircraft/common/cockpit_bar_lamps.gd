class_name CockpitBarLamps
extends Node
## The three green bars on the A320 FCU and EFIS pushbuttons (aircraft.json cockpit.bar_lamps), lit by CockpitLamps.lit
## (the autoflight mode or the EFIS selection, never the press) and drawn by annunciator_bars.gdshader: the unlit bars
## when off, soft green bars when on. Brightness: CockpitLamps.bar_energy (steady by day, low and dimmable at night).
##   pivots      buttons whose glb already has a lamp_<pivot> overlay (AP1, AP2, A/THR, LOC, APPR)
##   split       {name: [x, y, z]} lit-bar overlays baked into a static mesh (EXPED, FD, LS, the ND option buttons), at
##               FlightGear model-frame points (x aft, y right, z up). Their triangles (UV inside uv_lit, centroid within
##               NEAR of the point) are copied into a lamp_<name> mesh GAP in front, which hides the baked lit art.
##   mesh, material   the static mesh node and its surface that hold those overlays;  uv_lit  [u0, v0, u1, v1]
##   dim_offset  UV step from the lit bars to the unlit bars in the button atlas

const SHADER := preload("res://aircraft/common/annunciator_bars.gdshader")
const GAP := 0.0004
const NEAR := 0.012

var _lamps: Array = []  # {name, mat: ShaderMaterial, lit: float, e: float}


func build(interior: Node, cfg: Dictionary) -> int:
	var off := _vec2(cfg.get("dim_offset", [0.0, 0.0]))
	for p in cfg.get("pivots", []):
		var mi := interior.find_child("lamp_" + str(p), true, false) as MeshInstance3D
		if mi != null and mi.mesh != null:
			_add(mi, str(mi.name), _tex(mi.mesh, 0), off)
	if cfg.get("split") is Dictionary:
		_split(interior, cfg, off)
	set_process(not _lamps.is_empty())
	return _lamps.size()


func names() -> Array:
	return _lamps.map(func(l): return l.name)


func _process(_dt: float) -> void:
	var night := LightLogic.night_factor(Props.get_f("environment/sun_elev_deg", 30.0))
	var dim := Props.get_f("controls/lights/panel", LightLogic.PANEL_NIGHT_DEFAULT)
	var pw := Props.get_b("systems/electrical/powered", true)
	var e := CockpitLamps.bar_energy(night, dim, pw)
	for l in _lamps:
		var on := 1.0 if pw and CockpitLamps.lit(l.name) else 0.0
		if on != l.lit:
			l.lit = on
			(l.mat as ShaderMaterial).set_shader_parameter("lit", on)
		if not is_equal_approx(e, l.e):
			l.e = e
			(l.mat as ShaderMaterial).set_shader_parameter("energy", e)


func _add(mi: MeshInstance3D, lamp_name: String, tex: Texture2D, off: Vector2) -> void:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("dim_offset", off)
	m.set_shader_parameter("lit", 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamps.append({"name": lamp_name, "mat": m, "lit": 0.0, "e": -1.0})


func _split(interior: Node, cfg: Dictionary, off: Vector2) -> void:
	var src := interior.find_child(str(cfg.get("mesh", "")), true, false) as MeshInstance3D
	if src == null or src.mesh == null:
		return
	var surf := -1
	for i in src.mesh.get_surface_count():
		var mat := src.mesh.surface_get_material(i)
		if mat != null and mat.resource_name == str(cfg.get("material", "")):
			surf = i
	if surf < 0:
		return
	var rel := _relative(src, interior)
	var a := src.mesh.surface_get_arrays(surf)
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		idx = PackedInt32Array(range(pos.size()))
	var box: Array = cfg.get("uv_lit", [0.0, 0.0, 1.0, 1.0])
	var tex := _tex(src.mesh, surf)
	var split: Dictionary = cfg.split
	for k in split:
		var want := Vector3(float(split[k][0]), float(split[k][1]), float(split[k][2]))
		var mesh := _lamp_mesh(pos, uv, idx, box, rel, want)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "lamp_" + str(k)
		mi.mesh = mesh
		mi.transform = src.transform
		src.get_parent().add_child(mi)
		_add(mi, str(mi.name), tex, off)


## The overlay triangles near `want` (FlightGear frame), pushed GAP toward the pilot (+x aft in the glb frame).
func _lamp_mesh(pos: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array, box: Array, rel: Transform3D,
		want: Vector3) -> ArrayMesh:
	var v := PackedVector3Array()
	var t := PackedVector2Array()
	var n := PackedVector3Array()
	for i in range(0, idx.size() - 2, 3):
		var c := (uv[idx[i]] + uv[idx[i + 1]] + uv[idx[i + 2]]) / 3.0
		if c.x < float(box[0]) or c.y < float(box[1]) or c.x > float(box[2]) or c.y > float(box[3]):
			continue
		var g: Vector3 = rel * ((pos[idx[i]] + pos[idx[i + 1]] + pos[idx[i + 2]]) / 3.0)
		if Vector3(g.x, -g.z, g.y).distance_to(want) > NEAR:
			continue
		var fn := (pos[idx[i + 1]] - pos[idx[i]]).cross(pos[idx[i + 2]] - pos[idx[i]]).normalized()
		if (rel.basis * fn).x < 0.0:
			fn = -fn
		for j in 3:
			v.append(pos[idx[i + j]] + fn * GAP)
			t.append(uv[idx[i + j]])
			n.append(fn)
	if v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = t
	arr[Mesh.ARRAY_NORMAL] = n
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _relative(n: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


static func _tex(mesh: Mesh, surf: int) -> Texture2D:
	var m := mesh.surface_get_material(surf) as BaseMaterial3D
	return m.albedo_texture if m != null else null


static func _vec2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a.size() >= 2 else Vector2.ZERO
