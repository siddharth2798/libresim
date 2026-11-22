class_name JetwayStandin
extends MeshInstance3D
## Far stand-in of one jetway (HLOD, VisRanges): a single box over the raised tube in its average seen colour. Beyond
## `near` (the bridge covers about NEAR_PX pixels on a 1080p frame) the rig's dozen parts give way to this one box, and the
## box goes at the usual VisRanges pixel limit. The parts have this box as their visibility_parent, so they are only drawn
## while it is hidden for being too close; on Forward+ they cross-fade (fade mode DEPENDENCIES over the begin margin).
## Godot 4.7.2 shows a parent's dependencies again while the parent fades out at its far end, so the far end has no margin.
## The Mobile renderer draws no range fades at all (a switch is a cut there; at these sizes it is a few pixels).
## Pinned (the bridge is out at the player's aircraft, JetwayRig): the parts are always drawn and the box is off.

const GROUP := "jetway_standin"
const NEAR_PX := 16.0  # pixels the bridge spans where the box takes over (1080p, VisRanges.REF_FOV_DEG)
## Boxed: the raised tube (tunnel sections 1-3 and the hood, 3.8 to 6.3 m up). Not boxed: what reaches down toward the
## apron (tunnel 4's skirt, the cab drum, stairs, scissor lift, wheel support: a box down to the ground reads as a wall),
## signs, the rotunda, the canopy.
const BOXED := ["Tunnel1", "Tunnel2", "Tunnel3", "Hood"]

var base_near := 0.0  # High preset, unzoomed (VisRanges.detail / zoom scale it)
var base_far := 0.0
var pinned := false
var _parts: Array[GeometryInstance3D] = []


## Build the stand-in of `rig` (in the tree, at its rest pose) and hand its parts over to it. Returns null for a rig
## without meshes.
static func attach(rig: Node3D) -> JetwayStandin:
	var box := AABB()
	var first := true
	var parts: Array[GeometryInstance3D] = []
	var col := Vector3.ZERO
	var w := 0.0
	for n in rig.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		parts.append(gi)
		gi.set_meta("no_vis_range", true)  # VisRanges.tag_tree leaves the rig to its stand-in
		if gi is MeshInstance3D and _boxed(gi, rig):
			var a: AABB = _rel(gi, rig) * gi.get_aabb()
			box = a if first else box.merge(a)
			first = false
			var c := _albedo(gi as MeshInstance3D)
			var k := a.get_volume() + 1.0
			col += Vector3(c.r, c.g, c.b) * k
			w += k
	if first:
		return null
	var s := JetwayStandin.new()
	s.name = "Standin"
	s.set_meta("vis_standin", true)
	s.mesh = _unit_box()  # one mesh and one material for every stand-in: they draw as one instanced batch
	s.material_override = _material(col / maxf(w, 1e-3))
	s.scale = box.size.max(Vector3.ONE * 0.1)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # far away: shadows are sub-pixel
	s.position = box.get_center()
	var size := VisRanges.size_of(box)
	s.base_far = VisRanges.end_for(size)
	s.base_near = s.base_far * VisRanges.MIN_PX / NEAR_PX
	rig.add_child(s)
	s._parts = parts
	s.add_to_group(GROUP)
	s.set_pinned(float(rig.get("progress")) > 0.0)
	return s


## Transform of n in rig's frame (works outside the tree too, e.g. the jetway audit).
static func _rel(n: Node3D, rig: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var nd: Node = n
	while nd != rig and nd is Node3D:
		t = (nd as Node3D).transform * t
		nd = nd.get_parent()
	return t


static var _box: BoxMesh
static var _mats := {}  # quantised colour -> StandardMaterial3D


static func _unit_box() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
	return _box


## A shared material per colour, quantised (all jetways of an airport usually share one).
static func _material(avg: Vector3) -> StandardMaterial3D:
	var q := (avg * 16.0).round() / 16.0
	if not _mats.has(q):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(q.x, q.y, q.z)
		mat.roughness = 0.6
		_mats[q] = mat
	return _mats[q]


static func _boxed(n: Node, rig: Node) -> bool:
	while n != rig and n != null:
		if str(n.name) in BOXED:
			return true
		n = n.get_parent()
	return false


static func _albedo(mi: MeshInstance3D) -> Color:
	var m := mi.material_override
	if m == null and mi.mesh and mi.mesh.get_surface_count() > 0:
		m = mi.get_active_material(0)
	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		return bm.albedo_color * _seen_colour(mi.mesh, bm.albedo_texture)
	return Color(0.72, 0.74, 0.76)


static var _seen := {}  # [mesh rid, texture rid] -> colour


## The colour a textured mesh shows on average: its albedo texture sampled at each triangle's UV centre, weighted by
## the triangle's area (a texture atlas's own average says nothing about the parts this mesh uses). Once per mesh.
static func _seen_colour(mesh: Mesh, t: Texture2D) -> Color:
	if t == null or mesh == null or mesh.get_surface_count() == 0:
		return Color.WHITE
	var key := [mesh.get_rid(), t.get_rid()]
	if _seen.has(key):
		return _seen[key]
	var c := Color.WHITE
	var img := t.get_image()
	var arr := mesh.surface_get_arrays(0)
	var uv = arr[Mesh.ARRAY_TEX_UV]
	if img != null and not img.is_empty() and uv is PackedVector2Array and not (uv as PackedVector2Array).is_empty():
		if img.is_compressed():
			img.decompress()
		img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var ids: PackedInt32Array = idx if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty() else PackedInt32Array(range(v.size()))
		var sum := Color(0, 0, 0, 0)
		var w := 0.0
		for i in range(0, ids.size() - 2, 3):
			var area := (v[ids[i + 1]] - v[ids[i]]).cross(v[ids[i + 2]] - v[ids[i]]).length()
			var q: Vector2 = (uv[ids[i]] + uv[ids[i + 1]] + uv[ids[i + 2]]) / 3.0
			sum += img.get_pixel(clampi(int(fposmod(q.x, 1.0) * 64.0), 0, 63), clampi(int(fposmod(q.y, 1.0) * 64.0), 0, 63)) * area
			w += area
		if w > 0.0:
			c = sum / w
	_seen[key] = c
	return c


## The bridge is (or stops being) out at the player's aircraft: always draw its parts.
func set_pinned(on: bool) -> void:
	pinned = on
	refresh()


## Apply ranges for the current preset and zoom (VisRanges.refresh_all).
func refresh() -> void:
	var on := VisRanges.enabled and not pinned
	visible = on
	var k := VisRanges.detail * VisRanges.zoom
	visibility_range_begin = base_near * k
	visibility_range_begin_margin = base_near * k * maxf(VisRanges.fade, 0.02)
	visibility_range_end = base_far * k
	visibility_range_end_margin = 0.0
	visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DEPENDENCIES
	for p in _parts:
		if is_instance_valid(p):
			p.visibility_parent = p.get_path_to(self) if on else NodePath()
