extends RefCounted
## Jetway audit on the real data (airport_ops.json, terrain, building collision footprints, the landmark terminal
## models' collision raster): builds an airport's jet bridges as AirportOps does (JetwayBuild) and measures per
## movable bridge where its root meets the terminal, the wheels against the apron, the cab floor height, the rest
## pose against the taxi lanes and the docked pose against an A320's door. Used by tests/test_jetway_terminal.gd and
## tests/debug_jetway_audit.gd. legacy(): the same root / wheel numbers for the layout before tools/jetway_net.py
## (one bridge per OSM way, hinged at the end farther from a stand, the whole model scaled by clamp(len/22, .6, 1.8)).

const LINK_TOUCH := 1.5  # segment ends this close to another segment are joined
const MARCH := 0.25
const FAR := 60.0

var cache: TerrainTileCache
var bc := BuildingCollision.new()
var solid := {}  # the landmark terminal model's raster (SolidGrid), {} when the airport has none
var rings: Array[PackedVector2Array] = []
var def: AircraftDef


func _init(c: TerrainTileCache) -> void:
	cache = c
	def = AircraftDef.load_def("a320")


func h(e: float, n: float) -> float:
	return cache.height_at(e, n)


## Load what the building test needs around an airport's jet bridges.
func load_airport(icao: String, a: Dictionary) -> void:
	solid = {}
	rings.clear()
	var lm = Paths.load_json("terminals/landmarks.json") if FileAccess.file_exists(Paths.data("terminals/landmarks.json")) else null
	if lm is Dictionary:
		for r in lm.get(icao, []):
			var ring := PackedVector2Array()
			for p in r:
				ring.append(Vector2(p[0], p[1]))
			rings.append(ring)
	var glb := Paths.data("terminals/%s.glb" % icao)
	var meta = Paths.load_json("terminals/%s_model.json" % icao) if FileAccess.file_exists(glb) else null
	if meta is Dictionary:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(glb, st) == OK:
			var root: Node3D = doc.generate_scene(st)
			var o := Vector3(meta.origin[0], meta.origin[1], meta.origin[2])
			var verts := PackedVector3Array()
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				for v in (mi as MeshInstance3D).mesh.get_faces():
					var g: Vector3 = (mi as MeshInstance3D).transform * v
					verts.append(Vector3(o.x + g.x, o.y - g.z, o.z + g.y))
			solid = SolidGrid.build(verts, o.z, "t")
			root.free()
	for jb in a.jetbridges:
		for p in jb.pts:
			bc.load_now(p[0], p[1])


## Is (p, height z) inside a terminal / building?
func inside(p: Vector2, z: float) -> bool:
	if not solid.is_empty():
		var c := ((p - (solid.o as Vector2)) / float(solid.cell)).floor()
		if c.x >= 0 and c.y >= 0 and c.x < solid.nx and c.y < solid.ny:
			var k := int(c.y) * int(solid.nx) + int(c.x)
			if solid.zmin[k] <= z and z <= solid.zmax[k]:
				return true
	for ring in rings:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
	var out := []
	bc.near(p.x, p.y, 0.0, out)
	for rec in out:
		if rec.base - 0.5 <= z and z <= rec.top and Geometry2D.is_point_in_polygon(p, rec.poly):
			return true
	return false


## Signed distance from a free end to the facade at tunnel height: > 0 a gap in the air (march outward along `out`),
## < 0 the end is that deep in the wall (march back toward `back_to`); FAR + 1 = no building out there.
func facade(end: Vector2, out: Vector2, back_to: Vector2) -> float:
	var z := h(end.x, end.y) + JetwayPose.FLOOR_Y + 1.2
	if inside(end, z):
		var s := 0.0
		var n := maxf(end.distance_to(back_to), MARCH)
		while s < n and inside(end + (back_to - end).normalized() * s, z):
			s += MARCH
		return -s
	var t := 0.0
	while t < FAR:
		t += MARCH
		if inside(end + out * t, z):
			return t
	return FAR + 1.0


## The free ends of the fixed structure rotunda k belongs to: its stub, the jetlinks joined to it and the other
## rotundas' stubs those reach. Returns [[end, outward unit, inner point]].
func free_ends(k: int, stubs: Array, links: Array) -> Array:
	var segs := stubs.duplicate()
	for l in links:
		segs.append([Vector2(l.a[0], l.a[1]), Vector2(l.b[0], l.b[1])])
	var seen := {k: true}
	var todo := [k]
	while not todo.is_empty():
		var i: int = todo.pop_back()
		for j in segs.size():
			if not seen.has(j) and _touch(segs[i], segs[j]):
				seen[j] = true
				todo.append(j)
	var out := []
	for i in seen:
		for e in 2:
			var p: Vector2 = segs[i][e]
			var q: Vector2 = segs[i][1 - e]
			if i < stubs.size() and e == 0:
				continue  # a rotunda column itself
			var free := true
			for j in seen:
				if j != i and _pt_seg(p, segs[j][0], segs[j][1]) < LINK_TOUCH:
					free = false
			if free:
				out.append([p, (p - q).normalized(), q])
	return out


func _touch(a: Array, b: Array) -> bool:
	return minf(minf(_pt_seg(a[0], b[0], b[1]), _pt_seg(a[1], b[0], b[1])),
		minf(_pt_seg(b[0], a[0], a[1]), _pt_seg(b[1], a[0], a[1]))) < LINK_TOUCH


static func _pt_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


## Lowest point of a mesh (world) and the terrain under it: [height above ground of the lowest point, xy].
func _low(mi: MeshInstance3D, origin_shift: Vector3) -> Array:
	var bb := mi.get_aabb()
	var lo := Vector3(0, INF, 0)
	for i in 8:
		var p := mi.global_transform * bb.get_endpoint(i) + origin_shift
		if p.y < lo.y:
			lo = p
	var c := mi.global_transform * bb.get_center() + origin_shift
	return [lo.y - h(c.x, -c.z), Vector2(c.x, -c.z)]


## Rows for every movable bridge of an airport, built under `host` (in the tree) as the game does.
func measure(icao: String, a: Dictionary, host: Node) -> Array:
	load_airport(icao, a)
	var root := Node3D.new()
	host.add_child(root)
	var rigs := JetwayBuild.build(root, a, h, null, load("res://world/models/vehicles/jetway.glb"), def)
	var edges := _taxi_edges(a)
	var rows := []
	var stubs := []  # every rotunda's fixed stub [column, stub end]: the fixed structure a link may join
	for rig in rigs:
		stubs.append([rig.terminal, rig.terminal - Vector2.from_angle(rig._back_yaw) * (JetwayPose.PIVOT_X - JetwayPose.STUB_X)])
	var docked := {}
	for k in rigs.size():
		var rig: JetwayRig = rigs[k]
		var row := {"k": k, "rot": rig.terminal, "ends": [], "wheel": [], "floor_agl": [], "docks": rig.cands.size()}
		var rot1 := rig.find_child("Rotunda1", true, false) as MeshInstance3D
		row.stub_err = 0.0  # the drawn stub against the one assumed here
		if rot1 and not rot1.is_queued_for_deletion():
			var bb := rot1.get_aabb()
			var se := rot1.global_transform * Vector3(bb.position.x, bb.get_center().y, bb.get_center().z)
			row.stub_err = Vector2(se.x, -se.z).distance_to(stubs[k][1])
		for fe in free_ends(k, stubs, a.get("jetlinks", [])):
			row.ends.append({"p": fe[0], "d": facade(fe[0], fe[1], fe[2])})
		for p in [rig.rest] + rig.cands.map(func(c): return c.pose):
			rig.apply(p)
			row.wheel.append(_low(rig.find_child("SupportBogie", true, false), Vector3.ZERO)[0])
			var hood := rig.find_child("Hood", true, false) as MeshInstance3D
			row.floor_agl.append(_low(hood, Vector3.ZERO)[0])
		rig.apply(rig.rest)
		row.buried = inside(rig.terminal + Vector2.from_angle(rig.rest.yaw) * 1.0, h(rig.terminal.x, rig.terminal.y) + JetwayPose.FLOOR_Y + 1.2)
		row.rest_lane = _lane_clear(JetwayPose.tip_of(rig.terminal, rig.rest), edges)
		row.dock_err = 0.0
		for c in rig.cands:
			for st in a.stands:
				if st.jetbridge and GroundParams.cg_at_stand(st, def).distance_to(c.cg) < 0.01:
					docked[st] = true
					row.dock_err = maxf(row.dock_err, JetwayPose.tip_of(rig.terminal, c.pose).distance_to(GroundParams.door_tip(st, def)))
		rows.append(row)
	root.free()
	if not rows.is_empty():
		rows[0].gates_docked = docked.size()
	return rows


## Jet-bridge gates an A320 docks at with the layout before (one bridge per OSM way, hinged at its terminal end).
func legacy_gates_docked(a: Dictionary) -> int:
	var ways := []
	for jb in a.jetbridges:
		ways.append(JetwayDocks.ends({"pts": jb.pts}, a.stands))
	var dy := func(_t: Vector2, _tip: Vector2) -> float: return 0.0
	var n := {}
	for k in ways.size():
		for c in JetwayDocks.candidates(k, ways, a.stands, dy, def):
			n[c.cg] = true
	return n.size()


## The same root and wheel numbers for the layout the game drew before (see the header).
func legacy(icao: String, a: Dictionary) -> Array:
	load_airport(icao, a)
	var rows := []
	for jb in a.jetbridges:
		var e := JetwayDocks.ends({"pts": jb.pts}, a.stands)
		var t: Vector2 = e.terminal
		var d: Vector2 = (e.cab - t).normalized()
		var kx := clampf(e.cab.distance_to(t) / 22.0, 0.6, 1.8)
		var se := t - d * 5.24 * kx
		var foot := t + d * JetwayPose.SUPPORT_X * kx
		rows.append({"k": rows.size(), "rot": t, "ends": [{"p": se, "d": facade(se, -d, t)}],
			"wheel": [h(t.x, t.y) - h(foot.x, foot.y)], "buried": inside(t + d * 2.0 * kx, h(t.x, t.y) + JetwayPose.FLOOR_Y + 1.2)})
	return rows


func _taxi_edges(a: Dictionary) -> Array:
	var out := []
	var nodes: Dictionary = a.taxi.nodes
	for ed in a.taxi.edges:
		if ed[4] in ["taxiway", "taxilane"] and nodes.has(ed[0]) and nodes.has(ed[1]):
			var w := float(ed[3]) if str(ed[3]).is_valid_float() else 15.0
			out.append([Vector2(nodes[ed[0]][0], nodes[ed[0]][1]), Vector2(nodes[ed[1]][0], nodes[ed[1]][1]), maxf(w, 10.0) * 0.5])
	return out


## Distance from the rest hood to the nearest taxiway / taxilane edge beyond its half width (< 0: on the lane).
static func _lane_clear(p: Vector2, edges: Array) -> float:
	var best := INF
	for ed in edges:
		best = minf(best, _pt_seg(p, ed[0], ed[1]) - float(ed[2]))
	return best


## Jet-bridge gates no movable bridge docks at, and why: [{ref, cab_m (nearest drawn cab end to the door), len, twist_deg}].
func undocked(a: Dictionary) -> Array:
	var ways := []
	for jb in a.jetbridges:
		var e := JetwayDocks.ends(jb, a.stands)
		if not e.is_empty():
			ways.append(e)
	var out := []
	var dy := func(_t: Vector2, _tip: Vector2) -> float: return 0.0
	var served := {}
	for k in ways.size():
		for c in JetwayDocks.candidates(k, ways, a.stands, dy, def):
			served[c.cg] = true
	for st in a.stands:
		if not st.jetbridge or served.has(GroundParams.cg_at_stand(st, def)):
			continue
		var tip := GroundParams.door_tip(st, def)
		var best := {}
		var bd := INF
		for w in ways:
			if (w.cab as Vector2).distance_to(tip) < bd:
				bd = (w.cab as Vector2).distance_to(tip)
				best = w
		var hd := deg_to_rad(float(st.heading_deg))
		var cab_dir := Vector2(cos(hd), -sin(hd))
		var drum: Vector2 = tip - cab_dir * JetwayPose.CAB_LEN
		var d: Vector2 = drum - best.terminal
		out.append({"ref": st.ref, "src": st.get("src", ""), "cab_m": bd, "len": d.length(),
			"twist_deg": rad_to_deg(absf(JetwayPose.angle_diff(atan2(cab_dir.y, cab_dir.x), atan2(d.y, d.x))))})
	return out
