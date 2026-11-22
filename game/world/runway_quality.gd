class_name RunwayQuality
extends RefCounted
## Runway detail per graphics preset: the global shader parameter `runway_detail` (project.godot shader globals) read
## by world/runway_v2.gdshader. 0 Low: the baked look and paint only (Mobile); 1 Medium: + near-field sealant lines and
## tyre streaks; 2 High: + aggregate texture / normal and inset light fittings; 3 Ultra / Max: + near block cracks.
## Graphics.apply_to_scene calls apply().

const LEVEL := {"low": 0, "medium": 1, "high": 2, "ultra": 3, "max": 3}


static func level(preset: String) -> int:
	return int(LEVEL.get(preset, 2))


static func apply(preset: String) -> void:
	RenderingServer.global_shader_parameter_set("runway_detail", level(preset))
