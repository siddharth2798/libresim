class_name SkyParams
extends RefCounted
## Writes the sky shader's uniforms (world/sky_clouds.gdshader) only when they really change.
## Godot redraws the sky's radiance cubemap (the ambient light and the reflections on water and aircraft) after ANY
## write to a sky uniform, even of the same value. SkyTime, NightSky and CloudInside stage their values here each
## frame; flush() then writes a uniform only when it moved more than a small step from the value last written
## (about half an 8-bit colour level, or half a pixel for a direction), or reached exactly 0 or 1. A slow drift so
## arrives in steps too small to see, and a still sky leaves the cubemap alone. Sky.process_mode is INCREMENTAL
## (world/flight.tscn), so even a changing sky spreads the cubemap work over several frames.

const STEP_FLOAT := 0.002
const STEP_COLOR := 0.0015  # per channel, sRGB 0..1 (an 8-bit level is 0.0039)
const STEP_DIR := 0.0005  # radians, for unit vectors (moon_dir, sun_dir_u); half a pixel at 1080p
const STEP_VEC2 := 0.0004  # cirrus drift in its texture units: half a pixel of the finest wisp at the zenith
## Finer steps by name: the horizon dip moves the drawn horizon (0.001 is about a pixel), so it follows the bent
## ground (curvature.gdshaderinc) closely.
const STEP_BY_NAME := {&"horizon_dip": 0.0002}

var mat: ShaderMaterial
var writes := 0  # uniforms actually written (tests, profiling)
var _sent := {}  # name -> value last written
var _want := {}  # name -> value staged this frame


func _init(m: ShaderMaterial = null) -> void:
	mat = m


## Stage a value for this frame (the last stage of a name wins).
func stage(name: StringName, value: Variant) -> void:
	_want[name] = value


## The value staged this frame, else the value last written, else the material's own.
func want(name: StringName) -> Variant:
	if _want.has(name):
		return _want[name]
	if _sent.has(name):
		return _sent[name]
	return mat.get_shader_parameter(name) if mat else null


## Write the staged values that changed enough; returns how many were written.
func flush() -> int:
	var n := 0
	for name in _want:
		var v: Variant = _want[name]
		if _sent.has(name) and not changed(_sent[name], v, STEP_BY_NAME.get(name, -1.0)):
			continue
		_sent[name] = v
		if mat:
			mat.set_shader_parameter(name, v)
		n += 1
	_want.clear()
	writes += n
	return n


## True when `b` is far enough from `a` to be worth a write (and so a radiance update). step < 0: by type.
static func changed(a: Variant, b: Variant, step := -1.0) -> bool:
	if typeof(a) != typeof(b):
		return true
	match typeof(b):
		TYPE_FLOAT:
			return absf(b - a) > (step if step >= 0.0 else STEP_FLOAT) or (a != b and (b == 0.0 or b == 1.0))
		TYPE_COLOR:
			var d: float = maxf(maxf(absf(b.r - a.r), absf(b.g - a.g)), absf(b.b - a.b))
			return d > STEP_COLOR or (d > 0.0 and (b == Color.BLACK or b == Color.WHITE))
		TYPE_VECTOR3:
			return (b - a).length() > STEP_DIR
		TYPE_VECTOR2:
			return (b - a).length() > STEP_VEC2
	return a != b
