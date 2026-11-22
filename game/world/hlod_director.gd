class_name HlodDirector
extends Node
## Keeps the draw-distance helpers in step with the camera (child of AirportOps), a few times a second:
## - VisRanges zoom from the camera's field of view (a tower or fly-by zoom stretches every range);
## - occlusion culling on the main viewport on or off by OcclusionRules (camera height above the ground).

const CHECK_S := 0.2

var height_at := Callable()  # (east, north) -> ground height (m); unset: 0
var _t := 0.0
var _first := true  # the project setting starts the viewport with culling on: the first check decides afresh


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = CHECK_S
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	VisRanges.set_zoom(get_tree(), cam.fov)
	var w := FloatingOrigin.to_world(cam.global_position)
	var g := float(height_at.call(w.x, w.y)) if height_at.is_valid() else 0.0
	var vp := get_viewport()
	var was := vp.use_occlusion_culling and not _first
	_first = false
	var on := OcclusionRules.want(was, w.z - g, get_tree().get_node_count_in_group(OcclusionRules.GROUP))
	if on != vp.use_occlusion_culling:
		vp.use_occlusion_culling = on
