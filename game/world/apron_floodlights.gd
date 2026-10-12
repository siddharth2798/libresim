class_name ApronFloodlights
extends RefCounted
## Apron floodlight masts on big airports: one 25 m mast per cluster of stands, with
## emissive lamp heads (light points), a fake light pool on the ground (additive decal)
## and, near the camera only, a few real OmniLights shared by all masts (see RunwayLights).

const MAST_H := 25.0
const CLUSTER := 140.0  # stands within one grid cell share a mast
const MIN_STANDS := 20  # airports with fewer stands get no masts
const POOL_D := 110.0
const RUNWAY_CLEAR := 60.0  # no mast closer than this to a runway's edge, or past its ends
const WARM := Color(1.0, 0.8, 0.55)


## Mast positions (ENU) for a stand list: one per occupied CLUSTER cell, set off toward
## the nose-in side (terminal / service road) so it stands clear of the parked aircraft.
## runways (the airport's, from runways.json): a mast never stands in or beside a runway (a cluster
## of GA stands at a runway end used to put one there), nor where a C172 is meant to be (a stand,
## its pushback swing, a taxiway: ObstacleRegistry corridors): the other side of the cluster, else none.
static func masts(stands: Array, runways: Array = []) -> Array:
	if stands.size() < MIN_STANDS:
		return []
	var cells := {}
	for s in stands:
		var k := Vector2i(floori(s.x / CLUSTER), floori(s.y / CLUSTER))
		if not cells.has(k):
			cells[k] = []
		cells[k].append(s)
	var out := []
	for k in cells:
		var group: Array = cells[k]
		if group.size() < 2:
			continue
		var c := Vector2.ZERO
		var nose := Vector2.ZERO
		for s in group:
			c += Vector2(s.x, s.y)
			var hd := deg_to_rad(float(s.heading_deg))
			nose += Vector2(sin(hd), cos(hd))
		c /= group.size()
		var spots := [c]
		if nose.length() > 0.5:
			spots = [c + nose.normalized() * 28.0, c - nose.normalized() * 28.0, c]
		for p in spots:
			if clear_of_runways(p, runways) and not ObstacleRegistry.overlaps_corridor(ObstacleShapes.box(p, 1.0, 1.0, 0.0, 0.0, 0.0, "")):
				out.append(p)
				break
	return out


static func clear_of_runways(p: Vector2, runways: Array) -> bool:
	for r in runways:
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		var u := (b - a).normalized()
		var along := (p - a).dot(u)
		if absf((p - a).cross(u)) < float(r.width) * 0.5 + RUNWAY_CLEAR and along > -RUNWAY_CLEAR and along < a.distance_to(b) + RUNWAY_CLEAR:
			return false
	return true


## Lamp heads of each mast into s (light points, warm, omnidirectional).
static func add_heads(masts_: Array, hf: Callable, s: LightSet) -> void:
	for m in masts_:
		var h: float = hf.call(m.x, m.y) + MAST_H
		for k in 4:
			var a := k * PI * 0.5 + PI * 0.25
			s.add(m.x + cos(a) * 0.9, m.y + sin(a) * 0.9, h, WARM, Vector2.ZERO, 0.0, 0.0, false, 0.0, 1.4)


## Mast poles + ground pools as MultiMeshInstances (ENU anchor as in LightSet).
static func meshes(masts_: Array, hf: Callable, anchor: Vector2, pool_mat: Material) -> Array:
	if masts_.is_empty():
		return []
	var pole := CylinderMesh.new()
	pole.top_radius = 0.25
	pole.bottom_radius = 0.4
	pole.height = MAST_H
	pole.radial_segments = 6
	pole.rings = 1
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.55, 0.56, 0.58)
	pm.metallic = 0.4
	pole.material = pm
	var plane := PlaneMesh.new()
	plane.size = Vector2(POOL_D, POOL_D)
	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	poles.mesh = pole
	poles.instance_count = masts_.size()
	var pools := MultiMesh.new()
	pools.transform_format = MultiMesh.TRANSFORM_3D
	pools.mesh = plane
	pools.instance_count = masts_.size()
	for k in masts_.size():
		var m: Vector2 = masts_[k]
		var h: float = hf.call(m.x, m.y)
		var r := Vector3(m.x - anchor.x, h, -(m.y - anchor.y))
		poles.set_instance_transform(k, Transform3D(Basis(), r + Vector3(0, MAST_H * 0.5, 0)))
		pools.set_instance_transform(k, Transform3D(Basis(), r + Vector3(0, 0.25, 0)))
	var a := MultiMeshInstance3D.new()
	a.name = "flood_masts"
	a.multimesh = poles
	var b := MultiMeshInstance3D.new()
	b.name = "flood_pools"
	b.multimesh = pools
	b.material_override = pool_mat
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return [a, b]
