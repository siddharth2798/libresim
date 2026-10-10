class_name Clouds
extends MultiMeshInstance3D
## Cumulus layer from billboard puffs (MultiMesh, one draw call). Clouds are
## placed per 2 km world cell by a hash, so they stay put in the world and drift
## with the wind aloft. Rebuilt when the camera moves a cell or settings change.
## Props: weather/cloud_base_ft (AMSL), weather/cloud_cover (0..1).
## Publishes environment/in_cloud (bool) when the camera is inside a puff.

const CELL := 2000.0
const RADIUS := 26000.0
const THICK := 700.0  # layer depth (m)

var _drift := Vector2.ZERO
var _key := ""
var _puffs: Array = []  # [Vector3 enu centre, radius]


func _ready() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	multimesh.mesh = q
	var m := ShaderMaterial.new()
	m.shader = preload("res://world/cloud.gdshader")
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 1e6
	FloatingOrigin.shifted.connect(func(_d): _key = "")


func _hash(x: int, y: int, k: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (k * 83492791)
	return float(posmod(h, 100003)) / 100003.0


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w: Vector3 = Weather._from_dir_to_ned(Props.get_f("weather/aloft_dir_deg"), Props.get_f("weather/aloft_kt") * Units.KT)
	_drift += Vector2(w.y, w.x) * dt  # east, north
	var base := Units.ft_to_m(Props.get_f("weather/cloud_base_ft", 4500.0))
	var cover := Props.get_f("weather/cloud_cover")
	var c := FloatingOrigin.to_world(cam.global_position)
	var cx := floori((c.x - _drift.x) / CELL)
	var cy := floori((c.y - _drift.y) / CELL)
	var key := "%d,%d,%.0f,%.2f,%.0f,%.0f" % [cx, cy, base, cover, FloatingOrigin.origin.x, FloatingOrigin.origin.y]
	if key != _key or Engine.get_process_frames() % 30 == 0:
		_key = key
		_rebuild(cx, cy, base, cover)
	var m := material_override as ShaderMaterial
	m.set_shader_parameter("daylight", clampf((Props.get_f("environment/sun_elev_deg") + 4.0) / 14.0, 0.0, 1.0))
	var inside := false
	for p in _puffs:
		if (p[0] as Vector3).distance_to(c) < p[1] * 0.45:
			inside = true
			break
	Props.set_v("environment/in_cloud", inside)


func _rebuild(cx: int, cy: int, base: float, cover: float) -> void:
	_puffs.clear()
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var n := int(RADIUS / CELL)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var gx := cx + i
			var gy := cy + j
			if _hash(gx, gy, 0) > cover:
				continue
			var centre := Vector2((gx + _hash(gx, gy, 1)) * CELL, (gy + _hash(gx, gy, 2)) * CELL) + _drift
			var size := lerpf(500.0, 1400.0, _hash(gx, gy, 3)) * (0.6 + cover * 0.6)
			var puffs := 4 + int(_hash(gx, gy, 4) * 6.0)
			for k in puffs:
				var off := Vector3(_hash(gx, gy, 10 + k) - 0.5, _hash(gx, gy, 20 + k) * 0.6, _hash(gx, gy, 30 + k) - 0.5) * Vector3(size, THICK, size)
				var p := Vector3(centre.x + off.x, centre.y + off.z, base + THICK * 0.3 + off.y)
				var r := size * lerpf(0.5, 0.9, _hash(gx, gy, 40 + k))
				_puffs.append([p, r])
				xforms.append(Transform3D(Basis.from_scale(Vector3(r, r * 0.75, 1.0)), FloatingOrigin.to_render(p)))
				customs.append(Color(_hash(gx, gy, 50 + k), lerpf(0.85, 1.0, off.y / THICK + 0.3), 0, 0))
	multimesh.instance_count = xforms.size()
	for i in xforms.size():
		multimesh.set_instance_transform(i, xforms[i])
		multimesh.set_instance_custom_data(i, customs[i])
