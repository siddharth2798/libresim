class_name Curvature
extends RefCounted
## CPU twin of world/curvature.gdshaderinc (visual Earth curvature, docs/GRAPHICS-PLAN.md G4), for the tests and
## for anything that has to place something on the drawn (bent) ground far away. Keep both in step.
## Render-space positions; eye = terrain_eye (the camera), focus = ground_focus (the aircraft, far away if none).

const R := 6371000.0
const SHADERS := ["res://world/terrain.gdshader", "res://world/building.gdshader", "res://world/terminal.gdshader",
	"res://world/tree.gdshader", "res://world/tree_mesh.gdshader", "res://world/strip.gdshaderinc",
	"res://world/ground_paint.gdshader", "res://world/light_point.gdshaderinc"]  # everything drawn far away


## Metres a point at render-space wp is drawn below its true height.
static func drop(wp: Vector3, eye: Vector3, focus := Vector3(1e9, 0.0, 1e9)) -> float:
	var d := Vector2(wp.x - eye.x, wp.z - eye.z)
	var keep := (1.0 - smoothstep(300.0, 700.0, Vector2(wp.x - focus.x, wp.z - focus.z).length())) \
		* (1.0 - smoothstep(4000.0, 8000.0, Vector2(focus.x - eye.x, focus.z - eye.z).length()))
	return d.length_squared() * (0.5 / R) * (1.0 - keep)


## Local-space offset that lowers a vertex by `dm` metres in world y under basis b (no shear).
static func local_offset(b: Basis, dm: float) -> Vector3:
	return -dm * Vector3(b.x.y / b.x.length_squared(), b.y.y / b.y.length_squared(), b.z.y / b.z.length_squared())
