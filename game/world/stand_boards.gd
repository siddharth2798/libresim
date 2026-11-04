class_name StandBoards
extends RefCounted
## Stand number boards at contact stands: a 2 x 1 m sign on a post on the stand centre line in front of the
## terminal facade (the same facade ApronLightLayout puts the floods on), facing the arriving aircraft on the
## lead-in line, the stand's number in yellow (unshaded: backlit, reads day and night). A board whose post would
## stand in a stand / taxiway corridor is left out (AirportLights). Only drawn within VIS_M of the camera.

const H := 4.5  # post height (bottom of the board above the ground)
const BOARD := Vector2(2.0, 1.0)
const VIS_M := 900.0
const YELLOW := Color(1.0, 0.82, 0.2)


## Board text of a stand ref: "Bay V20" -> "V20", "12" -> "12"; "" when it has no number.
static func label(ref: String) -> String:
	var t := ref.strip_edges()
	for p in ["Bay ", "Stand ", "Gate "]:
		if t.begins_with(p):
			t = t.substr(p.length())
	return t.strip_edges()


## Boards [{p: Vector2 ENU, heading (rad, the way the board faces), text}] for the contact stands of an airport.
static func boards(stands: Array, ops: Dictionary) -> Array:
	var jet := ApronLightLayout.jet_segments(ops)
	var out := []
	for s in stands:
		var t := label(str(s.get("ref", "")))
		var f := ApronLightLayout.facade(s, ops.get("gates", []), jet)
		if t == "" or f == Vector2.INF:
			continue
		var hd := deg_to_rad(float(s.heading_deg))
		var p := f - Vector2(sin(hd), cos(hd)) * 4.0
		if out.any(func(o): return o.p.distance_to(p) < 4.0):  # overlapping (MARS) stands: one board
			continue
		out.append({"p": p, "heading": hd + PI, "text": t})
	return out


## The boards as nodes under one Node3D (ENU anchor as in LightSet): a 2 x 1 m sign box on a post, the number
## on the face toward the stand only (single-sided, so never mirrored), a plain back.
static func build(list: Array, hf: Callable, anchor: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "stand_boards"
	if list.is_empty():
		return root
	var box := BoxMesh.new()
	box.size = Vector3(BOARD.x, BOARD.y, 0.18)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.06, 0.06, 0.07)
	bm.roughness = 0.6
	box.material = bm
	var post := CylinderMesh.new()
	post.top_radius = 0.09
	post.bottom_radius = 0.11
	post.height = H
	post.radial_segments = 6
	post.rings = 1
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.5, 0.51, 0.53)
	pm.metallic = 0.4
	post.material = pm
	for b in list:
		var n := Node3D.new()
		var p: Vector2 = b.p
		n.position = Vector3(p.x - anchor.x, hf.call(p.x, p.y), -(p.y - anchor.y))
		n.rotation.y = -float(b.heading) + PI  # node -Z faces the compass heading; the sign's face is its +Z side
		var pole := MeshInstance3D.new()
		pole.mesh = post
		pole.position = Vector3(0, H * 0.5, -0.15)
		pole.visibility_range_end = VIS_M
		n.add_child(pole)
		var q := MeshInstance3D.new()
		q.mesh = box
		q.position = Vector3(0, H + BOARD.y * 0.5, 0)
		q.visibility_range_end = VIS_M
		n.add_child(q)
		var l := Label3D.new()
		l.text = b.text
		l.font_size = 96
		l.pixel_size = 0.0075 * minf(1.0, 3.0 / maxf(b.text.length(), 1.0))  # ~0.7 m tall glyphs, long refs fit the board
		l.outline_size = 0
		l.double_sided = false
		l.modulate = YELLOW
		l.position = Vector3(0, H + BOARD.y * 0.5, 0.1)
		l.visibility_range_end = VIS_M
		n.add_child(l)
		root.add_child(n)
	return root
