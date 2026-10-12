class_name OpsSolids
extends RefCounted
## Collision for the ground-ops dressing AirportOps draws at an airport: jetways, parked ground
## vehicles, windsock poles. Footprints are the models' own bounding boxes (oriented rectangles),
## registered in ObstacleRegistry under one group per airport.
## Keep-out: the vehicle layout is made for airliner stands, so a C172 parked at a stand, pushed back
## from it or taxiing on a taxiway would overlap some of them. Dressing that touches an
## OpsCorridors corridor is dropped (not drawn, not solid): every stand and taxiway stays usable.

const LABELS := {"fuel_truck": "a parked vehicle (fuel truck)", "gpu": "a parked vehicle (ground power unit)",
	"baggage_tug": "a parked vehicle (baggage tug)", "baggage_cart": "a parked vehicle (baggage cart)",
	"apron_bus": "a parked vehicle (apron bus)", "fire_truck": "a parked vehicle (fire truck)", "jetway": "a jetway"}
static var _aabbs := {}  # model name -> AABB in the model's own frame

var group := ""


func _init(group_name: String) -> void:
	group = group_name


## Model-space bounding box of a placed model (cached per kind). n must be inside the tree.
static func model_aabb(kind: String, n: Node3D) -> AABB:
	if _aabbs.has(kind):
		return _aabbs[kind]
	var inv := n.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = inv * m.global_transform * m.get_aabb()
		out = a if first else out.merge(a)
		first = false
	_aabbs[kind] = out
	return out


## Footprint record of a placed model: n.transform is relative to the ops root (x east, -z north).
func model_record(kind: String, n: Node3D, ground: float) -> Dictionary:
	var a := model_aabb(kind, n)
	var poly := PackedVector2Array()
	for c in [Vector3(a.position.x, 0, a.position.z), Vector3(a.end.x, 0, a.position.z), Vector3(a.end.x, 0, a.end.z), Vector3(a.position.x, 0, a.end.z)]:
		var p: Vector3 = n.transform * c
		poly.append(Vector2(p.x, -p.z))
	return ObstacleShapes.poly(poly, ground - 0.5, ground + maxf(a.end.y * n.transform.basis.get_scale().y, 0.5), LABELS.get(kind, "a parked vehicle"))


## Register a placed model. keep_clear: drop it (return false) when it touches a corridor.
func add_model(kind: String, n: Node3D, ground: float, keep_clear := true) -> bool:
	var rec := model_record(kind, n, ground)
	if keep_clear and ObstacleRegistry.overlaps_corridor(rec):
		return false
	ObstacleRegistry.add(group, rec)
	return true


## The jetway's real shape (elevated tunnel, support, rotunda) as a raster of its triangles, so a
## C172 can taxi under the tunnel but not into the rotunda or the support. n: placed, inside the tree.
func add_jetway(n: Node3D, ground: float) -> void:
	var verts := PackedVector3Array()
	var to_root := n.transform * n.global_transform.affine_inverse()  # world -> ops root frame
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var t: Transform3D = to_root * m.global_transform
		for v in m.mesh.get_faces():
			var p: Vector3 = t * v
			verts.append(Vector3(p.x, -p.z, p.y))  # ops root: x east, y up, z -north
	var rec := SolidGrid.build(verts, ground, "a jetway", 0.0)
	if not rec.is_empty() and not _low_part_in_corridor(rec):
		ObstacleRegistry.add(group, rec)


## Does a part of the raster that a C172 (2.5 m high) would hit stand in a corridor? Then that jetway
## (a misplaced OSM way) is drawn but not solid, so stands and taxiways stay usable.
static func _low_part_in_corridor(rec: Dictionary) -> bool:
	var o: Vector2 = rec.o
	var cell: float = rec.cell
	for k in rec.zmax.size():
		if rec.zmax[k] > -INF and rec.zmin[k] < 2.5 + rec.base:
			var c := o + Vector2(k % int(rec.nx) + 0.5, k / int(rec.nx) + 0.5) * cell
			if ObstacleRegistry.in_corridor(c.x, c.y):
				return true
	return false


## A thin vertical pole (inflated to radius). Dropped when it stands in a corridor.
static func add_pole(group_name: String, c: Vector2, radius: float, height: float, ground: float, label: String) -> bool:
	if ObstacleRegistry.overlaps_corridor(ObstacleShapes.box(c, radius, radius, 0.0, 0.0, 0.0, "")):
		return false
	ObstacleRegistry.add(group_name, ObstacleShapes.disc(c, radius, ground - 0.3, ground + height, label))
	return true


func clear() -> void:
	ObstacleRegistry.remove_group(group)
