class_name TerrainBump
extends RefCounted
## Visual bump amplitude for the terrain shader (GRAPHICS-PLAN G9). Metres, before the noise sign.
## The shader repeats FAR_M, FULL_M and the smoothstep; it does not read this script.
## TerrainQuadtree.height_at never calls it: the offset is not a ground height.

const PEAK_M := 2.0
const FULL_M := 1000.0  # full peak within this camera distance
const FAR_M := 2000.0  # gone at this distance and beyond

static var _sent_amp := NAN  # last terrain_bump_amp written (the global is process-wide, so is this)
static var writes := 0  # globals actually written (tests)


## Sets the terrain_bump_amp global for `quality`, only when it changed (TerrainQuadtree calls it each frame).
static func publish(quality: String) -> void:
	var amp := peak_m(quality)
	if amp == _sent_amp:
		return
	_sent_amp = amp
	RenderingServer.global_shader_parameter_set("terrain_bump_amp", amp)
	writes += 1


## Preset peak (m): low 0, medium half, high and above full. Any other name is 0.
static func peak_m(quality: String) -> float:
	match quality:
		"low":
			return 0.0
		"medium":
			return PEAK_M * 0.5
		"high", "ultra", "max":
			return PEAK_M
		_:
			return 0.0


## Peak metres at `dist_m`. `paved` is pavement, a road or water: the bump is then 0.
static func amplitude_m(quality: String, dist_m: float, paved: bool) -> float:
	if paved or dist_m >= FAR_M:
		return 0.0
	var peak := peak_m(quality)
	if peak <= 0.0:
		return 0.0
	return peak * _fade(dist_m)


## 1 inside FULL_M, hermite down to 0 at FAR_M (GLSL smoothstep(FULL_M, FAR_M, dist)).
static func _fade(dist_m: float) -> float:
	if dist_m <= FULL_M:
		return 1.0
	var t := (dist_m - FULL_M) / (FAR_M - FULL_M)
	var s := t * t * (3.0 - 2.0 * t)
	return 1.0 - s
