extends Node
## Occlusion culling (graphics Phase 2): the project setting, when it runs (OcclusionRules), and occluders made at run
## time from a model's walls (OccluderBuild / OccluderRings / OccluderJobs) that always stay inside what is drawn.


func teardown() -> void:
	for c in get_children():
		c.free()


func test_occlusion_culling_is_on_in_the_project() -> String:
	var on := bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false))
	return "" if on else "rendering/occlusion_culling/use_occlusion_culling must be on (project.godot)"


func test_occlusion_runs_near_the_ground_only() -> String:
	if OcclusionRules.disabled:
		return ""  # a --no-occlusion run
	if not OcclusionRules.want(false, 5.0, 3):
		return "on the apron with occluders loaded it should run"
	if OcclusionRules.want(false, 5.0, 0):
		return "without occluders it costs CPU for nothing"
	if OcclusionRules.want(false, 1500.0, 3):
		return "on approach from 1500 m it should be off"
	if not OcclusionRules.want(true, (OcclusionRules.ON_BELOW_M + OcclusionRules.OFF_ABOVE_M) * 0.5, 3) \
			or OcclusionRules.want(false, (OcclusionRules.ON_BELOW_M + OcclusionRules.OFF_ABOVE_M) * 0.5, 3):
		return "between the two heights it keeps its state (no flicker on a low pass)"
	return ""


## A plain box building (BoxMesh walls): one occluder prism MARGIN inside every wall, below the roof, above the ground.
func test_box_building_occluder_is_inside_the_walls() -> String:
	var box := BoxMesh.new()
	box.size = Vector3(60.0, 20.0, 40.0)
	var faces := Transform3D(Basis.IDENTITY, Vector3(100.0, 10.0, -50.0)) * box.get_faces()
	var out := OccluderBuild.build(faces)
	var verts: PackedVector3Array = out[0]
	if verts.size() < 16:
		return "a 60 x 40 x 20 m block should give four occluder walls (%d vertices)" % verts.size()
	var inner := AABB(Vector3(70.0, 0.0, -70.0), Vector3(60.0, 20.0, 40.0)).grow(-OccluderBuild.MARGIN + 0.01)
	for v in verts:
		if not inner.has_point(v):
			return "occluder vertex %s is not MARGIN inside the block" % v
	return ""


## An L-shaped building and a courtyard block (walls only, as tools/terminal_geom.py makes them): every occluder point
## lies inside the footprint, at least MARGIN from its outline, and nothing covers the courtyard.
func test_concave_and_courtyard_footprints_stay_inside() -> String:
	var l_shape := PackedVector2Array([Vector2(0, 0), Vector2(80, 0), Vector2(80, 30), Vector2(30, 30), Vector2(30, 90), Vector2(0, 90)])
	var outer := PackedVector2Array([Vector2(200, 0), Vector2(300, 0), Vector2(300, 100), Vector2(200, 100)])
	var court := PackedVector2Array([Vector2(230, 30), Vector2(230, 70), Vector2(270, 70), Vector2(270, 30)])  # wound the other way
	var faces := PackedVector3Array()
	for ring in [l_shape, outer, court]:
		faces.append_array(_walls(ring, 0.0, 18.0))
	var out := OccluderBuild.build(faces)
	var verts: PackedVector3Array = out[0]
	if verts.is_empty():
		return "no occluders for an L block and a courtyard block"
	for v in verts:
		var p := Vector2(v.x, -v.z)
		var in_l := Geometry2D.is_point_in_polygon(p, l_shape)
		var in_block := Geometry2D.is_point_in_polygon(p, outer) and not Geometry2D.is_point_in_polygon(p, court)
		if not (in_l or in_block):
			return "occluder point %s lies outside the buildings (in the courtyard or the open)" % p
		var ring := l_shape if in_l else outer
		if _dist(p, ring) < OccluderBuild.MARGIN - 0.01:
			return "occluder point %s is closer than MARGIN to a wall" % p
		if v.y < OccluderBuild.MARGIN - 0.01 or v.y > 18.0 - OccluderBuild.MARGIN + 0.01:
			return "occluder height %.1f is not MARGIN inside 0..18 m" % v.y
	return ""


## The real landmark terminals (data/processed/terminals), when the data is there: occluders exist and fit inside the
## model's own bounds.
func test_terminal_occluders_fit_inside_the_model() -> String:
	var dir := Paths.data("terminals")
	var tried := 0
	for icao in ["VABB", "VAPO", "VOCI"]:
		var path := dir.path_join(icao + ".glb")
		if not FileAccess.file_exists(path):
			continue
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			continue
		var root: Node3D = doc.generate_scene(state)
		var faces := OccluderBuild.faces_under(root)
		root.free()
		var bounds := AABB(faces[0], Vector3.ZERO)
		for p in faces:
			bounds = bounds.expand(p)
		var out := OccluderBuild.build(faces)
		var verts: PackedVector3Array = out[0]
		tried += 1
		if verts.size() < 8:
			return "%s: the terminal should have occluder walls" % icao
		for v in verts:
			if not bounds.grow(0.01).has_point(v):
				return "%s: occluder vertex %s outside the model's bounds" % [icao, v]
	return "" if tried > 0 or not DirAccess.dir_exists_absolute(dir) else "terminal models found but none loaded"


## OccluderJobs builds on a worker and hangs the occluder under the model root, so it moves with the root
## (FloatingOrigin shifts reposition the root).
func test_occluder_job_attaches_under_the_model_and_moves_with_it() -> String:
	if OcclusionRules.disabled:
		return ""
	var root := Node3D.new()
	add_child(root)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(50.0, 16.0, 50.0)
	mi.mesh = box
	mi.position = Vector3(0.0, 8.0, 0.0)
	root.add_child(mi)
	var jobs := OccluderJobs.new()
	jobs.start("t", root)
	var t0 := Time.get_ticks_msec()
	while jobs.pending() > 0 and Time.get_ticks_msec() - t0 < 5000:
		jobs.poll()
		OS.delay_msec(5)
	var oi := root.get_node_or_null("Occluder") as OccluderInstance3D
	if oi == null or not oi.is_in_group(OcclusionRules.GROUP):
		return "the finished occluder should be a child of the model root, in the occluders group"
	var before := oi.global_position - root.global_position
	root.position += Vector3(-5000.0, 0.0, 5000.0)  # a floating-origin shift
	var after := oi.global_position - root.global_position
	return "" if before.is_equal_approx(after) else "the occluder must move with its model"


static func _walls(ring: PackedVector2Array, y0: float, y1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var p := [Vector3(a.x, y0, -a.y), Vector3(b.x, y0, -b.y), Vector3(b.x, y1, -b.y), Vector3(a.x, y1, -a.y)]
		out.append_array([p[0], p[1], p[2], p[0], p[2], p[3]])
	return out


static func _dist(p: Vector2, ring: PackedVector2Array) -> float:
	var d := INF
	for i in ring.size():
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()])))
	return d
