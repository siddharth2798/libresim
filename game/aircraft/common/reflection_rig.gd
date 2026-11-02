class_name ReflectionRig
extends Node3D
## A ReflectionProbe for the aircraft: its glass and paint reflect the real surroundings (terrain,
## horizon, haze, clouds) and not only the Environment's sky. The probe captures the world without
## the aircraft (AIRCRAFT_LAYER and the interior are on layers the probe does not draw) from just
## above the airframe. It is re-captured only when ReflectionPolicy says the picture changed, never
## every frame (a capture draws the scenery six times). Box projection is off: far scenery has no
## parallax, so the cubemap serves a 1.2 km box and the aircraft needs no per-frame probe motion.
## Preset: ReflectionPolicy.PRESETS (Low off). Built by AircraftModel.

const BOX := Vector3(1200.0, 600.0, 1200.0)
const HIDDEN_LAYER := 1 << 10  # interior, bulbs, ...: not captured, still lit like layer 1
const LIFT := 1.5              # probe height above the aircraft origin (m)
const CHECK_S := 0.5

var _probe: ReflectionProbe
var _model: Node3D
var _cfg := {}
var _last := {}
var _since := 0.0
var _check := 0.0
var _captures := 0


static func attach(model: Node3D) -> ReflectionRig:
	var r := ReflectionRig.new()
	r.name = "ReflectionRig"
	model.add_child(r)
	r.build(model)
	return r


func build(model: Node3D) -> void:
	_model = model
	hide_from_probe(model)
	_probe = ReflectionProbe.new()
	_probe.top_level = true
	_probe.size = BOX
	_probe.box_projection = false
	_probe.interior = false
	_probe.enable_shadows = false
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.cull_mask = 0xFFFFF & ~LightLogic.AIRCRAFT_LAYER & ~HIDDEN_LAYER
	_probe.reflection_mask = LightLogic.AIRCRAFT_LAYER  # only the airframe is reflected on
	_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	add_child(_probe)
	FloatingOrigin.shifted.connect(_on_shift)
	Graphics.changed.connect(apply_preset)
	apply_preset(Graphics.preset)


## Cockpit and light geometry out of the capture: everything under `root` that is not on the
## airframe layer moves to HIDDEN_LAYER.
static func hide_from_probe(root: Node) -> void:
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		if (gi as GeometryInstance3D).layers != LightLogic.AIRCRAFT_LAYER:
			(gi as GeometryInstance3D).layers = HIDDEN_LAYER


func apply_preset(preset: String) -> void:
	_cfg = ReflectionPolicy.for_preset(preset)
	_probe.visible = _cfg.on
	_probe.max_distance = _cfg.far_m
	_probe.intensity = _cfg.intensity
	_last = {}  # capture again with the new settings
	_captures = 0


func _on_shift(delta_render: Vector3) -> void:
	_probe.global_position += delta_render  # the world moved, the probe stays where it was in it


func captures() -> int:
	return _captures


func _process(dt: float) -> void:
	_since += dt
	_check += dt
	if _check < CHECK_S or not _cfg.on or not _model.is_inside_tree():
		return
	_check = 0.0
	var cur := _now()
	if ReflectionPolicy.needs_refresh(_last, cur, _since, _cfg.gap_s, _captures):
		_capture(cur)


func _now() -> Dictionary:
	return ReflectionPolicy.snapshot(Props.get_f("environment/sun_elev_deg", 30.0),
		Props.get_v("fdm/position_enu", Vector3.ZERO), Props.get_f("fdm/alt_m"),
		Props.get_f("weather/cloud_cover"), Props.get_f("weather/precip"),
		Props.get_f("weather/visibility_m", 20000.0), Props.get_f("weather/cloud_base_ft", 4500.0))


## Move the probe onto the aircraft; a moved ONCE probe renders its cubemap again.
func _capture(cur: Dictionary) -> void:
	_probe.global_position = _model.global_position + Vector3(0.0, LIFT, 0.0)
	_last = cur
	_since = 0.0
	_captures += 1

