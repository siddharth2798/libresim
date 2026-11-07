class_name CloudTemporal
extends RefCounted
## Temporal cloud upscaling (GRAPHICS-PLAN G7). Pure functions: no nodes, no RenderingDevice.
## Step bands are the preset table in graphics_settings.gd (low 10, medium 16, high 24, ultra 40, max 64):
## below high stays full resolution, the high band (24..63, so high and ultra) marches at half, max (64+) at quarter.
## History is dropped when the camera jumps more than 50 m or the view turns more than 20 degrees.

const HALF_STEPS := 24
const QUARTER_STEPS := 64
const CUT_JUMP_M := 50.0
const CUT_TURN_RAD := 20.0 * PI / 180.0
const WEIGHT_HALF := 0.15 # share of this frame's march; the rest is reprojected history
const WEIGHT_QUARTER := 0.10


## 1 full, 2 half, 4 quarter. The march viewport is this many times smaller on each axis.
static func scale_for_steps(steps: int) -> int:
	if steps >= QUARTER_STEPS:
		return 4
	if steps >= HALF_STEPS:
		return 2
	return 1


## True when this frame must not blend with the previous one (a cut, a view switch, an origin shift).
static func history_reset(jump_m: float, turn_rad: float) -> bool:
	return jump_m > CUT_JUMP_M or turn_rad > CUT_TURN_RAD


## Current-frame weight in the history blend. 1 replaces history (full resolution, or a cut).
static func blend_weight(reset: bool, scale: int) -> float:
	if reset or scale <= 1:
		return 1.0
	if scale >= 4:
		return WEIGHT_QUARTER
	return WEIGHT_HALF


static func is_camera_cut(prev: Transform3D, cur: Transform3D) -> bool:
	return history_reset(prev.origin.distance_to(cur.origin), _turn(-prev.basis.z, -cur.basis.z))


## Sub-texel ray offset in full-view UV. Zero at full resolution, so Low / Medium are not jittered.
static func jitter_uv(frame: int, scale: int, view_px: Vector2) -> Vector2:
	if scale <= 1 or view_px.x < 1.0 or view_px.y < 1.0:
		return Vector2.ZERO
	var i := posmod(frame, 16)
	var j := Vector2(_halton(i, 2) - 0.5, _halton(i, 3) - 0.5)
	return Vector2(j.x * float(scale) / view_px.x, j.y * float(scale) / view_px.y)


## Current view-space point (camera looks down -Z) to the previous frame's screen UV.
## `reproj` maps current view space into previous clip space (reproj_matrix).
static func reproject_uv(view_pos: Vector3, reproj: Projection) -> Vector2:
	var c := reproj * Vector4(view_pos.x, view_pos.y, view_pos.z, 1.0)
	if c.w <= 1e-5:
		return Vector2(-1.0, -1.0)
	return Vector2(c.x / c.w * 0.5 + 0.5, c.y / c.w * 0.5 + 0.5)


## prev_proj * (previous view <- world <- current view). Same product as the motion-blur effect.
static func reproj_matrix(prev_xf: Transform3D, prev_proj: Projection, cur_xf: Transform3D) -> Projection:
	return prev_proj * Projection(prev_xf.affine_inverse() * cur_xf)


static func _turn(a: Vector3, b: Vector3) -> float:
	if a.length_squared() < 1e-12 or b.length_squared() < 1e-12:
		return 0.0
	return a.normalized().angle_to(b.normalized())


static func _halton(index: int, base: int) -> float:
	var f := 1.0
	var r := 0.0
	var n := index
	while n > 0:
		f /= float(base)
		r += f * float(n % base)
		n = int(float(n) / float(base))
	return r
