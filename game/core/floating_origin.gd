extends Node
## Autoload "FloatingOrigin". World positions are ENU metres (x east, y north,
## z up) held in 64-bit GDScript floats. Render space is Godot's Y-up frame
## relative to a movable origin so the camera stays near (0,0,0):
##   render = Vector3(e - origin.x, u, -(n - origin.y))
## The origin jumps in SHIFT_STEP increments when the focus point drifts too far.

signal shifted(delta_render: Vector3)

const SHIFT_STEP := 5000.0
## Shader floats are 32-bit: an absolute ENU origin of ~1e6 m (Kochi is ~950 km
## out) quantises to 0.06 m, which makes procedural patterns (water waves,
## facades) jitter. Shaders therefore get `pattern_origin` = origin - _wrap_base,
## kept below ~PATTERN_WRAP. _wrap_base re-snaps (to the PATTERN_WRAP grid) only
## once the origin has drifted more than PATTERN_WRAP from it, so patterns are
## world-stable over >= 25 km of travel and jump at most once per re-snap.
const PATTERN_WRAP := 50000.0

var origin := Vector2.ZERO  # ENU (east, north) of render-space (0,0,0)
var _wrap_base := Vector2.ZERO  # multiple of PATTERN_WRAP; see pattern_origin()


func to_render(enu: Vector3) -> Vector3:
	return Vector3(enu.x - origin.x, enu.z, -(enu.y - origin.y))


## Same as to_render, from 64-bit components (Vector3 is float32: ENU near 1e6 m
## would lose ~6 cm). origin is on the 5 km grid or set once, so it is exact.
func to_render_d(e: float, n: float, u: float) -> Vector3:
	return Vector3(e - origin.x, u, -(n - origin.y))


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
	_publish()
	shifted.emit(Vector3(-d.x, 0.0, d.y))


func set_origin(o: Vector2) -> void:
	var d := o - origin
	origin = o
	_publish()
	shifted.emit(Vector3(-d.x, 0.0, d.y))


## Origin relative to the current wrap base (small, float32-safe).
func pattern_origin() -> Vector2:
	return origin - _wrap_base


static func wrap_base(o: Vector2, base: Vector2) -> Vector2:
	if absf(o.x - base.x) <= PATTERN_WRAP and absf(o.y - base.y) <= PATTERN_WRAP:
		return base
	return Vector2(snappedf(o.x, PATTERN_WRAP), snappedf(o.y, PATTERN_WRAP))


## Shaders that need world-stable pattern coordinates (water waves, facades)
## read the global `pattern_origin`; never the absolute origin (float32).
func _publish() -> void:
	_wrap_base = wrap_base(origin, _wrap_base)
	RenderingServer.global_shader_parameter_set("pattern_origin", pattern_origin())
