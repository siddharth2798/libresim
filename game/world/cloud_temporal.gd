class_name CloudTemporal
extends RefCounted
## Temporal cloud upscaling (GRAPHICS-PLAN G7). Pure functions: no nodes, no RenderingDevice.
## Step bands are the preset table in graphics_settings.gd (low 10, medium 16, high 24, ultra 40, max 64):
## every preset up to ultra (1..63 steps) marches at half resolution, max (64+) at quarter. Low and Medium marched
## every pixel until study F16: the weakest presets paid the most per pixel. The depth copy (CloudDepthCopy) runs
## after the opaque pass on Forward+ and after the transparent pass on Mobile, which rejects POST_OPAQUE
## (CloudDepthCopy.callback_for). The Compatibility (OpenGL) renderer has no CompositorEffect, so it stays full
## resolution (scale_for).
## History is dropped when the camera jumps more than 50 m or the view turns more than 20 degrees.

const HALF_STEPS := 1
const QUARTER_STEPS := 64
const CUT_JUMP_M := 50.0
const CUT_TURN_RAD := 20.0 * PI / 180.0
const WEIGHT_HALF := 0.15 # share of this frame's march; the rest is reprojected history
const WEIGHT_QUARTER := 0.10
## Sub-texel jitter of the low-res march. Off: on a depth edge (the horizon, a windshield frame against the sky)
## each frame's jittered texel fell on the other side of the edge, and the edge blinked. Clouds are soft, so the
## history blend without jitter loses little detail.
const MARCH_JITTER := false


## scale_for_steps on renderers with a depth copy (Forward+, Mobile); 1 on Compatibility.
static func scale_for(steps: int, method := RenderingServer.get_current_rendering_method()) -> int:
	return 1 if method == "gl_compatibility" else scale_for_steps(steps)


## 1 full, 2 half, 4 quarter. The march viewport is this many times smaller on each axis. 0 steps (no clouds): 1.
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


## Sub-texel ray offset in full-view UV. Zero at full resolution.
static func jitter_uv(frame: int, scale: int, view_px: Vector2) -> Vector2:
	if scale <= 1 or view_px.x < 1.0 or view_px.y < 1.0:
		return Vector2.ZERO
	var i := posmod(frame, 16)
	var j := Vector2(_halton(i, 2) - 0.5, _halton(i, 3) - 0.5)
	return Vector2(j.x * float(scale) / view_px.x, j.y * float(scale) / view_px.y)


## The jitter the low-res march uses this frame: jitter_uv when MARCH_JITTER, else none.
static func march_jitter(frame: int, scale: int, view_px: Vector2) -> Vector2:
	return jitter_uv(frame, scale, view_px) if MARCH_JITTER else Vector2.ZERO


## Cloud extinction per metre at density 1 (volumetric_clouds.gdshader), and the near field with no cloud at all.
## cloud_upscale.gdshader applies max_alpha() to every pixel of both upscale passes (see there).
const CLOUD_EXT := 0.006
const NEAR_CLEAR_M := 6.0


## The most cloud (alpha) that can lie in front of a surface `dist_m` from the camera: the physical bound, and zero in
## the near field (the cockpit). The march at low resolution, the history blend and the one-frame-old depth copy can
## all put more on a pixel at a depth edge; this caps it with the pixel's own depth. Same maths as the shader.
static func max_alpha(dist_m: float) -> float:
	return (1.0 - exp(-maxf(dist_m, 0.0) * CLOUD_EXT)) * smoothstep(0.5 * NEAR_CLEAR_M, NEAR_CLEAR_M, dist_m)


## Metres from the camera to the cloud slab (0 inside it). A surface nearer than this is in front of every cloud,
## so the upscale draws no cloud on it: the windshield frame and the aircraft never pick up low-res sky blocks.
static func clear_dist(cam_alt_m: float, base_m: float, thick_m: float) -> float:
	if cam_alt_m < base_m:
		return base_m - cam_alt_m
	if cam_alt_m > base_m + thick_m:
		return cam_alt_m - base_m - thick_m
	return 0.0


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
