class_name AircraftLights
extends Node3D
## Exterior lights driven by Props controls/lights/* and bus power:
## nav (red left tip, green right tip, white tail), beacon (red, fin top, ~1 Hz),
## strobes (white wingtip double-flash), taxi + landing spot lights (cowling).
## Built by C172Model with its structural->local converter.

var _nav: Array[MeshInstance3D] = []
var _beacon: MeshInstance3D
var _strobes: Array[MeshInstance3D] = []
var _landing: SpotLight3D
var _taxi: SpotLight3D
var _t := 0.0


func build(s: Callable) -> void:
	_nav.append(_bulb(s.call(Vector3(1.1, -5.5, 1.5)), Color(1, 0.1, 0.05)))
	_nav.append(_bulb(s.call(Vector3(1.1, 5.5, 1.5)), Color(0.1, 1, 0.2)))
	_nav.append(_bulb(s.call(Vector3(6.6, 0.0, 0.7)), Color(1, 1, 0.95)))
	_beacon = _bulb(s.call(Vector3(6.0, 0.0, 2.1)), Color(1, 0.1, 0.05))
	_strobes.append(_bulb(s.call(Vector3(1.15, -5.52, 1.5)), Color(1, 1, 1)))
	_strobes.append(_bulb(s.call(Vector3(1.15, 5.52, 1.5)), Color(1, 1, 1)))
	_landing = _spot(s.call(Vector3(-0.9, -0.25, 0.1)), 4.0, 600.0, 9.0)
	_taxi = _spot(s.call(Vector3(-0.9, 0.25, 0.1)), 1.5, 250.0, 22.0)


func _bulb(p: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	mi.material_override = m
	mi.position = p
	add_child(mi)
	return mi


func _spot(p: Vector3, energy: float, rng: float, angle: float) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = p
	l.rotation_degrees = Vector3(-4.0, 0.0, 0.0)  # slightly down from the nose (-Z)
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_attenuation = 0.6
	l.shadow_enabled = false
	l.visible = false
	add_child(l)
	return l


func _glow(mi: MeshInstance3D, on: bool, energy := 6.0) -> void:
	(mi.material_override as StandardMaterial3D).emission_energy_multiplier = energy if on else 0.0


func _process(dt: float) -> void:
	_t += dt
	var pw := Props.get_b("systems/electrical/powered", true)
	var nav := pw and Props.get_b("controls/lights/nav")
	for b in _nav:
		_glow(b, nav, 4.0)
	_glow(_beacon, pw and Props.get_b("controls/lights/beacon") and fmod(_t, 1.1) < 0.15, 8.0)
	var ph := fmod(_t, 1.2)
	var flash := ph < 0.05 or (ph > 0.12 and ph < 0.17)
	for st in _strobes:
		_glow(st, pw and Props.get_b("controls/lights/strobe") and flash, 30.0)
	_landing.visible = pw and Props.get_b("controls/lights/landing")
	_taxi.visible = pw and Props.get_b("controls/lights/taxi")
