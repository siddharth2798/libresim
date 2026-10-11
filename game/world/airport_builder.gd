class_name AirportBuilder
extends Node3D
## Builds runway and taxiway surfaces from data/processed/runways.json
## (tools/09_runways.py). Each surface is a strip mesh anchored at its first
## point and re-positioned when the floating origin shifts.

const STEP := 20.0  # metres between cross-sections (follows the 30 m terrain lattice closely)
const LIFT := 0.12

var terrain: TerrainQuadtree
var data: Dictionary
var _items: Array = []  # [MeshInstance3D, anchor ENU Vector3]
var _shader := preload("res://world/runway.gdshader")


func build(t: TerrainQuadtree) -> void:
	terrain = t
	data = Paths.load_json("runways.json")
	if data == null:
		return
	for r in data.runways:
		var a: Dictionary = r.ends[0]
		var b: Dictionary = r.ends[1]
		_strip([Vector2(a.x, a.y), Vector2(b.x, b.y)], r.width, true, r.length)
	for tw in data.taxiways:
		var pts: Array[Vector2] = []
		for p in tw.pts:
			pts.append(Vector2(p[0], p[1]))
		_strip(pts, minf(tw.width, 23.0), false, 0.0)
	FloatingOrigin.shifted.connect(func(_d): _reposition())
	_reposition()


func _reposition() -> void:
	for it in _items:
		(it[0] as MeshInstance3D).position = FloatingOrigin.to_render(it[1])


## Densify a polyline and extrude it to a strip; UV = (across 0..1, metres along).
func _strip(pts: Array, width: float, is_runway: bool, length: float) -> void:
	var dense: Array[Vector2] = []
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(int(a.distance_to(b) / STEP), 1)
		for k in n:
			dense.append(a.lerp(b, float(k) / n))
	dense.append(pts[-1])
	if dense.size() < 2:
		return
	var anchor := Vector3(dense[0].x, dense[0].y, terrain.height_at(dense[0].x, dense[0].y))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	for i in dense.size():
		var p := dense[i]
		var dir := (dense[mini(i + 1, dense.size() - 1)] - dense[maxi(i - 1, 0)]).normalized()
		var side := Vector2(dir.y, -dir.x) * width * 0.5  # to the right of travel
		if i > 0:
			along += p.distance_to(dense[i - 1])
		for s in [-1.0, 1.0]:
			var q: Vector2 = p + side * s
			var h := terrain.height_at(q.x, q.y) + LIFT
			verts.append(Vector3(q.x - anchor.x, h - anchor.z, -(q.y - anchor.y)))
			uvs.append(Vector2((s + 1.0) * 0.5, along))
		if i > 0:
			var k := i * 2
			idx.append_array([k - 2, k, k - 1, k - 1, k, k + 1])  # clockwise seen from above
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("is_runway", is_runway)
	mat.set_shader_parameter("length_m", along if length <= 0.0 else length)
	mat.set_shader_parameter("width_m", width)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_items.append([mi, anchor])


## Start position on a runway: returns {pos: Vector2 ENU, heading_deg} or {}.
func runway_start(airport: String, ident: String) -> Dictionary:
	if data == null:
		return {}
	var rwys: Array = data.runways.filter(func(r): return r.airport == airport)
	rwys.sort_custom(func(a, b): return a.length > b.length)  # default: longest runway
	for r in rwys:
		for i in 2:
			var e: Dictionary = r.ends[i]
			if ident == "" or e.ident == ident:
				var hd := deg_to_rad(float(e.heading_true))
				var fwd := Vector2(sin(hd), cos(hd))
				var p := Vector2(e.x, e.y) + fwd * 25.0
				return {"pos": p, "heading_deg": float(e.heading_true), "ident": e.ident}
	return {}
