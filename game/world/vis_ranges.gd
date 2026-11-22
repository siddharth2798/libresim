class_name VisRanges
extends RefCounted
## Draw distances for small scenery (airport dressing, jetways, lamp masts, signs), chosen from what the eye can see
## rather than from any one machine's speed: an object is drawn while it covers at least MIN_PX pixels on a 1080p
## frame at the reference field of view, so its range is end_for(size) = size x (540 / tan(REF_FOV / 2)) / MIN_PX.
## The graphics preset scales it (detail = the preset's terrain lod_k / 1.6: Low 0.75 .. Max 1.5, the same level-of-detail
## ladder as the terrain), and a zoomed camera (tower, fly-by, telephoto) stretches it by tan(REF_FOV / 2) / tan(fov / 2)
## so nothing a zoom shows goes missing. Ranges fade (visibility_range_fade_mode SELF) over the last FADE share, so
## nothing pops. Ranged nodes keep their base range (High, unzoomed) in meta "vis_base" and sit in GROUP, so a preset
## or zoom change re-applies them all; a pinned node (meta "vis_pin", e.g. a jetway at the player's aircraft) is always
## drawn. --no-vis-ranges switches it all off (before / after renders and benches).

const REF_FOV_DEG := 60.0  # the chase view; the cockpit's 70 deg shows things smaller, so ranges are generous there
const MIN_PX := 3.0  # on High: below this many pixels on a 1080p frame an object is dropped
const REF_LOD_K := 1.6  # the High preset's lod_k (core/graphics_settings.gd)
const FADE := 0.05  # share of the range (each side of it) over which an object fades; Forward+ draws a fading object
## unbatched in the transparent pass, so a wider band costs draw calls (0.12 cost +10 % draws at VABB, 0.05 +3 %)
const GROUP := "vis_range"
const ZOOM_STEP := 1.25  # zoom is applied in steps of this factor (no re-apply on every small fov change)

static var detail := 1.0
static var zoom := 1.0
static var enabled := not OS.get_cmdline_user_args().has("--no-vis-ranges")
static var fade := _arg_fade()  # FADE, or --vis-fade=<share> for measurements (0 = no fade)


## The size that decides visibility: the square root of the AABB's largest face (a 30 x 4 m jetway side counts as 11 m,
## a 0.25 m wide, 28 m long painted line as 2.6 m).
static func size_of(box: AABB) -> float:
	var s := box.size.abs()
	var dims := [s.x, s.y, s.z]
	dims.sort()
	return sqrt(maxf(dims[1] * dims[2], 0.0))


## Base range (m, High preset, unzoomed) of an object of this size.
static func end_for(size_m: float) -> float:
	return size_m * 540.0 / tan(deg_to_rad(REF_FOV_DEG) * 0.5) / MIN_PX


## Preset scale from the preset's terrain lod_k.
static func detail_for(lod_k: float) -> float:
	return clampf(lod_k / REF_LOD_K, 0.5, 2.0)


## Zoom factor of a camera with this vertical field of view (1 at REF_FOV and wider), in ZOOM_STEP steps.
static func zoom_for(fov_deg: float) -> float:
	var z := tan(deg_to_rad(REF_FOV_DEG) * 0.5) / tan(deg_to_rad(clampf(fov_deg, 0.5, 179.0)) * 0.5)
	if z <= 1.0:
		return 1.0
	return pow(ZOOM_STEP, ceilf(log(z) / log(ZOOM_STEP) - 1e-4))


## The range (m) a node with this base gets now (0 = unlimited).
static func effective(base: float) -> float:
	return base * detail * zoom if enabled and base > 0.0 else 0.0


## Give gi a base range (High, unzoomed) and apply it.
static func set_range(gi: GeometryInstance3D, base: float) -> void:
	gi.set_meta("vis_base", base)
	gi.add_to_group(GROUP)
	apply(gi)


## Range from gi's own bounds (in its parent's frame, so a scaled node counts at its drawn size).
static func auto(gi: GeometryInstance3D) -> void:
	var base := end_for(size_of(Transform3D(gi.transform.basis, Vector3.ZERO) * gi.get_aabb()))
	if gi.visibility_range_end > 0.0 and not gi.has_meta("vis_base"):
		base = minf(base, gi.visibility_range_end)  # a shorter range set by its builder stands (e.g. vehicle ground decals)
	set_range(gi, base)


## Range every GeometryInstance3D under root by its size, except those marked meta "no_vis_range" and HLOD children
## (a visibility_parent decides for them, JetwayStandin).
static func tag_tree(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.has_meta("no_vis_range") or not gi.visibility_parent.is_empty() or gi.has_meta("vis_standin"):
			continue
		auto(gi)


static func apply(gi: GeometryInstance3D) -> void:
	var end := 0.0 if gi.get_meta("vis_pin", false) else effective(float(gi.get_meta("vis_base", 0.0)))
	gi.visibility_range_end = end
	gi.visibility_range_end_margin = end * maxf(fade, 0.02)  # without a fade the margin is hysteresis
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if end > 0.0 and fade > 0.0 \
		else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


static func _arg_fade() -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vis-fade="):
			return float(a.substr(11))
	return FADE


## Pin (always draw) or unpin every ranged node under root, root included.
static func pin(root: Node, on: bool) -> void:
	var nodes := root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		nodes.append(root)
	for n in nodes:
		if n.is_in_group(GROUP):
			n.set_meta("vis_pin", on)
			apply(n)
	for s in root.find_children("*", "", true, false):
		if s.has_method("set_pinned"):
			s.set_pinned(on)


## Re-apply every ranged node (preset or zoom changed). Stand-ins (JetwayStandin) refresh themselves too.
static func refresh_all(tree: SceneTree) -> void:
	for n in tree.get_nodes_in_group(GROUP):
		apply(n)
	for n in tree.get_nodes_in_group(JetwayStandin.GROUP):
		n.refresh()


## Graphics preset hook (core/graphics_settings.gd apply_to_scene).
static func set_detail(tree: SceneTree, lod_k: float) -> void:
	var d := detail_for(lod_k)
	if d != detail:
		detail = d
		refresh_all(tree)


## Camera hook (HlodDirector): re-applies only when the zoom step changes.
static func set_zoom(tree: SceneTree, fov_deg: float) -> void:
	var z := zoom_for(fov_deg)
	if z != zoom:
		zoom = z
		refresh_all(tree)
