class_name PostFxRules
extends RefCounted
## Which post effects run, and the motion-blur reset rules. Pure functions (no nodes, no RenderingDevice), tested by
## tests/test_post_fx.gd. core/post_fx.gd and world/postfx/* call them; effects never gate themselves.
## Every effect has a UserOptions toggle of the same name, a lowest preset and the renderers it runs on:
##   compute  = CompositorEffect with a compute shader: Forward+ always; Mobile only if it needs no motion vectors
##   canvas   = CanvasLayer screen pass after tonemapping / TAA / upscaling (any renderer)
##   spatial  = full-screen transparent quad with the screen / depth textures (Forward+ and Mobile)
##   env      = Environment / CameraAttributes settings (Forward+ and Mobile)

const PRESET_RANK := {"low": 0, "medium": 1, "high": 2, "ultra": 3, "max": 4}
const FX := {
	"motion_blur": {"min": "high", "renderers": ["forward_plus"]},  # needs the velocity buffer: Forward+ only
	"sun_shafts": {"min": "medium", "renderers": ["forward_plus"]},  # mobile has no resolved depth or storage colour buffer
	"sharpen": {"min": "high", "renderers": ["forward_plus", "mobile", "gl_compatibility"]},
	"color_grading": {"min": "low", "renderers": ["forward_plus", "mobile", "gl_compatibility"]},
	"heat_shimmer": {"min": "high", "renderers": ["forward_plus"]},  # Mobile stores colour at half range: an unverified copy
	"lens_rain": {"min": "medium", "renderers": ["forward_plus", "mobile", "gl_compatibility"]},
	"lens_effects": {"min": "low", "renderers": ["forward_plus", "mobile", "gl_compatibility"]},
	"depth_of_field": {"min": "low", "renderers": ["forward_plus", "mobile"]},
	"volumetric_fog": {"min": "high", "renderers": ["forward_plus"]},  # env: froxel fog + FogVolumes (world/volumetric_fog.gd)
}
## Camera views (CameraRig.Mode order); a camera that is not a CameraRig counts as OTHER (outside).
const VIEW_COCKPIT := 0
const VIEW_FREE := 3
const VIEW_OTHER := -1

## Motion blur: shutter = fraction of a 1/60 s frame the virtual shutter is open (0.5 = a 180 degree shutter).
const SHUTTER := 0.5
const REF_DT := 1.0 / 60.0
const MAX_BLUR_PX := 40.0
const BLUR_SAMPLES := 12
const SKIP_FRAMES := 2  # frames without blur after a cut: the previous transforms are stale for one frame, +1 margin
const CUT_MIN_JUMP_M := 25.0  # a camera move larger than this in one frame is a cut (fly-by re-placement, teleport)
const CUT_SPEED_MPS := 400.0  # ... unless it is below what this speed covers in the frame (x1.5)
const CUT_TURN_RAD := 0.6  # a camera turn of more than ~34 degrees in one frame is a cut (view switch)


static func rank(preset: String) -> int:
	return int(PRESET_RANK.get(preset, 0))  # unknown preset: treated as Low (never turns more on)


## Effect `fx` runs: its option is on, the preset is high enough and the renderer can draw it.
## extra: the effect's own condition (sharpen: TAA or a render scale != 1; DoF: replay / free view).
static func active(fx: String, preset: String, renderer: String, option_on: bool, extra := true) -> bool:
	if not FX.has(fx) or not option_on or not extra:
		return false
	return rank(preset) >= rank(FX[fx].min) and renderer in FX[fx].renderers


## All effect flags for a preset / renderer / options (UserOptions keys = effect names, plus "bloom").
## use_taa / render_scale: the viewport's, after Graphics applied the preset (sharpen_needed).
static func flags_for(preset: String, renderer: String, opts: Dictionary, use_taa: bool, render_scale: float) -> Dictionary:
	var out := {"bloom": bloom_on(preset, bool(opts.get("bloom", true)))}
	for fx in FX:
		var extra := sharpen_needed(use_taa, render_scale) if fx == "sharpen" else true
		out[fx] = active(fx, preset, renderer, bool(opts.get(fx, UserOptions.DEFAULTS.get(fx, false))), extra)
	return out


## Bloom = Environment glow: the option, but never on Low (integrated GPUs, PLAN.md §8b).
static func bloom_on(preset: String, option_on: bool) -> bool:
	return option_on and rank(preset) >= rank("medium")


## Sharpening only pays when the image was softened: TAA, or a render scale below / above 1 (FSR / bilinear).
static func sharpen_needed(use_taa: bool, render_scale: float) -> bool:
	return use_taa or absf(render_scale - 1.0) > 0.01


## Depth of field: never in the cockpit; in replay any outside view, otherwise only the free camera.
static func dof_wanted(view: int, replay_active: bool) -> bool:
	return view != VIEW_COCKPIT and (replay_active or view == VIEW_FREE)


## Lens rain sits on an outside camera's lens; the cockpit has its own windshield rain.
static func lens_rain_wanted(view: int) -> bool:
	return view != VIEW_COCKPIT


## True when the camera moved from `prev` to `cur` too far / turned too much in one frame to be motion: a cut.
static func is_cut(prev: Transform3D, cur: Transform3D, dt: float) -> bool:
	var jump := prev.origin.distance_to(cur.origin)
	if jump > maxf(CUT_MIN_JUMP_M, CUT_SPEED_MPS * maxf(dt, 0.0) * 1.5):
		return true
	var q := (prev.basis.orthonormalized().inverse() * cur.basis.orthonormalized()).get_rotation_quaternion()
	return q.get_angle() > CUT_TURN_RAD


## Frames left without blur. reset: origin shift / view switch this frame (from the driver); cut: is_cut().
static func next_skip(skip_left: int, reset: bool, cut: bool) -> int:
	return SKIP_FRAMES if reset or cut else maxi(skip_left - 1, 0)


## Blur length per unit of per-frame motion: normalised to a 1/60 s frame, so the streaks are the same length at
## 60 and 144 fps (a fixed exposure time). Clamped so a hitch (tiny / huge dt) cannot explode it.
static func blur_scale(shutter: float, dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	return clampf(shutter * REF_DT / dt, 0.0, 3.0 * shutter)


## Size of the aircraft (m): the larger of the wingspan and the ground footprint length. Defaults are the C172's.
static func aircraft_extent_m(def: AircraftDef) -> float:
	if def == null:
		return 11.0
	var span := float(def.config().get("metrics", {}).get("wingspan_m", 10.9))
	var g := def.section("ground")
	var length := float(g.get("ahead_m", 3.3)) + float(g.get("behind_m", 7.4))
	return maxf(span, length)


## The near_cut the blur shader gets: negative in the cockpit view, where everything nearer (cockpit, airframe) rides
## with the camera and is never blurred. The velocity buffer cannot be trusted there: every ~10 frames it carried a
## whole frame of the aircraft's travel and smeared the panel for one frame (a visible blink at speed).
static func blur_near_param(near_cut_m: float, view: int) -> float:
	return -absf(near_cut_m) if view == VIEW_COCKPIT else absf(near_cut_m)


## Pixels nearer than this (m) never get the camera-only reprojection: the aircraft and its cockpit, whichever view.
static func near_cutoff_m(cam_to_aircraft_m: float, extent_m: float) -> float:
	return cam_to_aircraft_m + extent_m
