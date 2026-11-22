class_name OcclusionRules
extends RefCounted
## When occlusion culling runs. Godot rasterises the occluders on the CPU every frame (Embree ray casts into a small depth
## buffer) and then skips objects found behind them. That pays where many separate objects hide behind big solid walls
## and the GPU or the draw calls are the limit: on the ground among terminals. From the air almost nothing is behind a
## wall, so the ray casts would be pure CPU cost (most on weak CPUs). So it runs only while the camera is near the ground
## (ON_BELOW_M, off again above OFF_ABOVE_M) and some occluder is loaded. The same rule on every machine.
## --no-occlusion switches it off (before / after renders and benches): no occluders are built. --occlusion-always runs
## it at any height (to measure what it would cost in the air).

const ON_BELOW_M := 150.0  # camera height above the ground (m) where it switches on ...
const OFF_ABOVE_M := 250.0  # ... and off again (hysteresis)
const GROUP := "occluders"  # OccluderInstance3D nodes made at run time (OccluderBuild.instance)

static var disabled := OS.get_cmdline_user_args().has("--no-occlusion")
static var always := OS.get_cmdline_user_args().has("--occlusion-always")


## Should the main viewport cull by occlusion now? was_on: its current state; agl: camera height above the ground (m);
## occluders: how many occluder nodes are loaded.
static func want(was_on: bool, agl: float, occluders: int) -> bool:
	if disabled or occluders <= 0:
		return false
	return always or agl < (OFF_ABOVE_M if was_on else ON_BELOW_M)
