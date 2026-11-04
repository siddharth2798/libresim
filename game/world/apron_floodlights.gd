class_name ApronFloodlights
extends RefCounted
## Apron floodlighting of one airport, from ApronLightLayout: masts and poles (one MultiMesh of cylinders scaled
## to each light's height, a lamp frame on top), lamp heads as light points (the "flood" group: seen from the air
## on approach), and per bank a fake light pool on the ground (light_pool.gdshader: what a spot at the lamp
## would put on the ground, soft cone edge) that fades out where ApronLamps lights the bank with a real
## SpotLight near the camera. Masts and poles are solid (OpsSolids.add_pole); facade floods have no pole.

const POLE_MESH_H := 10.0  # cylinder mesh height, scaled per light
const POOL_GAIN := {"mast": 1.0, "pole": 0.8, "facade": 0.9}
const VOL_BELOW := 12.0  # light volume under the ground (coarse terrain LODs, slopes) ...
const VOL_ABOVE := 20.0  # ... and above it (vehicles, aircraft up to the A320's fin)


## Lamp position (ENU, absolute height) of a bank: on the lamp frame, toward its aim.
static func lamp_pos(m: Dictionary, b: Dictionary, ground: float) -> Vector3:
	var d: Vector2 = b.aim - m.p
	var u := d.normalized() if d.length() > 0.1 else Vector2.UP
	var q: Vector2 = m.p + u * (0.3 if m.kind == "facade" else 0.9)
	return Vector3(q.x, q.y, ground + m.h - 0.4)


## Bank records for ApronLamps: {key, lamp (ENU), aim (ENU, on the ground), col, half_deg, throw (m)}.
static func bank_records(lights: Array, hf: Callable, icao: String) -> Array:
	var out := []
	for i in lights.size():
		var m: Dictionary = lights[i]
		var g: float = hf.call(m.p.x, m.p.y)
		for j in m.banks.size():
			var b: Dictionary = m.banks[j]
			var lp := lamp_pos(m, b, g)
			var aim := Vector3(b.aim.x, b.aim.y, hf.call(b.aim.x, b.aim.y))
			out.append({"key": "%s:%d:%d" % [icao, i, j], "lamp": lp, "aim": aim, "col": m.col,
				"half_deg": b.half_deg, "throw": lp.distance_to(aim), "kind": m.kind})
	return out


## Lamp heads into s (light points, omnidirectional), side by side across each bank's aim.
static func add_heads(lights: Array, hf: Callable, s: LightSet) -> void:
	for m in lights:
		var g: float = hf.call(m.p.x, m.p.y)
		for b in m.banks:
			var lp := lamp_pos(m, b, g)
			var u: Vector2 = (b.aim - m.p).normalized()
			var r := Vector2(u.y, -u.x)
			for k in b.heads:
				var o: float = (k - (b.heads - 1) * 0.5) * (0.7 if m.kind == "pole" else 1.0)
				s.add(lp.x + r.x * o, lp.y + r.y * o, lp.z, m.col, Vector2.ZERO, 0.0, 0.0, false, 0.0, 1.0 if m.kind == "pole" else 1.4)


## Poles, lamp frames and ground pools as MultiMeshInstances (ENU anchor as in LightSet).
static func meshes(lights: Array, hf: Callable, anchor: Vector2, pool_mat: Material) -> Array:
	var out := []
	var standing := lights.filter(func(m): return m.kind != "facade")
	if not standing.is_empty():
		out.append_array(_poles(standing, hf, anchor))
	var pools := []
	for m in lights:
		var g: float = hf.call(m.p.x, m.p.y)
		for b in m.banks:
			pools.append(_pool(m, b, g, anchor))
	if not pools.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var box := BoxMesh.new()  # a light volume: the shader lights whatever the depth buffer shows inside it
		box.size = Vector3(2.0, 2.0, 2.0)
		mm.mesh = box
		mm.instance_count = pools.size()
		for k in pools.size():
			mm.set_instance_transform(k, pools[k][0])
			mm.set_instance_color(k, pools[k][1])
			mm.set_instance_custom_data(k, pools[k][2])
		var mi := MultiMeshInstance3D.new()
		mi.name = "flood_pools"
		mi.multimesh = mm
		mi.material_override = pool_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(mi)
	return out


## [transform, colour (rgb, a = gain), custom (lamp height above the box centre, lamp offset behind the box
## centre, cos of the spot cone angle, aim offset ahead of the box centre)] of one bank's pool. The box (2 x 2 x 2,
## scaled; VOL_BELOW m under the ground to VOL_ABOVE above it) covers the cone's footprint: from where the near
## edge of the cone meets the ground (behind the mast foot when the cone reaches past the vertical) to where the
## far edge does (capped). light_pool.gdshader lights the ground, vehicles and aircraft seen inside it.
static func _pool(m: Dictionary, b: Dictionary, ground: float, anchor: Vector2) -> Array:
	var lp := lamp_pos(m, b, ground)
	var foot := Vector2(lp.x, lp.y)
	var dv: Vector2 = b.aim - foot
	var u := dv.normalized() if dv.length() > 0.1 else Vector2.UP
	var D := dv.length()
	var H := lp.z - ground
	var a := deg_to_rad(ApronLamps.cone_deg(float(b.half_deg)))  # the real SpotLight's cone (same light)
	var th := atan2(H, D)
	var near := -H * tan(th + a - PI * 0.5) if th + a > PI * 0.5 else H / tan(th + a)
	var far := minf(H / tan(maxf(th - a, deg_to_rad(6.0))), D * ApronLamps.RANGE_K + H)
	var mid := (near + far) * 0.5
	var half_len := (far - near) * 0.5 + 3.0
	var half_w := minf(tan(a) * Vector2(H, far).length() * 0.8, half_len * 1.1)
	var c := foot + u * mid
	var z := Vector3(u.x, 0.0, -u.y)  # render frame (x east, -z north): local +z points away from the light
	var x := Vector3.UP.cross(z)
	var hh := (VOL_ABOVE + VOL_BELOW) * 0.5
	var cy := ground + (VOL_ABOVE - VOL_BELOW) * 0.5
	var t := Transform3D(Basis(x * half_w, Vector3.UP * hh, z * half_len), Vector3(c.x - anchor.x, cy, -(c.y - anchor.y)))
	var col: Color = m.col
	col.a = float(POOL_GAIN[m.kind])
	return [t, col, Color(lp.z - cy, mid, cos(a), D - mid)]


static func _poles(lights: Array, hf: Callable, anchor: Vector2) -> Array:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.06
	pole.height = POLE_MESH_H
	pole.radial_segments = 6
	pole.rings = 1
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.55, 0.56, 0.58)
	pm.metallic = 0.4
	pm.roughness = 0.5
	pole.material = pm
	var frame := BoxMesh.new()
	frame.size = Vector3(1.0, 1.0, 1.0)
	frame.material = pm
	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	poles.mesh = pole
	poles.instance_count = lights.size()
	var frames := MultiMesh.new()
	frames.transform_format = MultiMesh.TRANSFORM_3D
	frames.mesh = frame
	frames.instance_count = lights.size()
	for k in lights.size():
		var m: Dictionary = lights[k]
		var h: float = m.h
		var g: float = hf.call(m.p.x, m.p.y)
		var r := Vector3(m.p.x - anchor.x, g, -(m.p.y - anchor.y))
		var thick := 7.0 if m.kind == "mast" else 2.5  # radius scale: 0.42 m at the foot of a mast
		poles.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(thick, h / POLE_MESH_H, thick)), r + Vector3(0, h * 0.5, 0)))
		var u: Vector2 = (m.banks[0].aim - m.p).normalized()
		var across := Vector3(u.y, 0.0, u.x) * (3.2 if m.kind == "mast" else 1.2)  # render frame, across the aim
		var along := Vector3(u.x, 0.0, -u.y) * (0.6 if m.kind == "mast" else 0.3)
		frames.set_instance_transform(k, Transform3D(Basis(across, Vector3.UP * 0.5, along), r + Vector3(0, h - 0.1, 0)))
	var a := MultiMeshInstance3D.new()
	a.name = "flood_masts"
	a.multimesh = poles
	var b := MultiMeshInstance3D.new()
	b.name = "flood_frames"
	b.multimesh = frames
	return [a, b]
