extends Node
## Autoload "FloatingOrigin". World positions are ENU metres (x east, y north,
## z up) held in 64-bit GDScript floats. Render space is Godot's Y-up frame
## relative to a movable origin so the camera stays near (0,0,0):
##   render = Vector3(e - origin.x, u, -(n - origin.y))
## The origin jumps in SHIFT_STEP increments when the focus point drifts too far.

signal shifted(delta_render: Vector3)

const SHIFT_STEP := 5000.0

var origin := Vector2.ZERO  # ENU (east, north) of render-space (0,0,0)


func to_render(enu: Vector3) -> Vector3:
	return Vector3(enu.x - origin.x, enu.z, -(enu.y - origin.y))


func to_world(r: Vector3) -> Vector3:
	return Vector3(r.x + origin.x, -r.z + origin.y, r.y)


## Call once per frame with the focus point (camera or aircraft), in ENU.
func update_focus(enu: Vector3) -> void:
	var dx := enu.x - origin.x
	var dy := enu.y - origin.y
	if absf(dx) < SHIFT_STEP and absf(dy) < SHIFT_STEP:
		return
	var new_origin := Vector2(snappedf(enu.x, SHIFT_STEP), snappedf(enu.y, SHIFT_STEP))
	var d := new_origin - origin
	origin = new_origin
	shifted.emit(Vector3(-d.x, 0.0, d.y))


func set_origin(o: Vector2) -> void:
	var d := o - origin
	origin = o
	shifted.emit(Vector3(-d.x, 0.0, d.y))
