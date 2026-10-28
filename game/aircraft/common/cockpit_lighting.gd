class_name CockpitLighting
extends Node3D
## C172S cockpit night lighting: internally lit instruments and the engine strip follow
## the PANEL dimmer (controls/lights/panel, 0..1) on bus power; the radio stack displays
## are light-emitting and stay readable; a warm glareshield flood (shadowless spot under the
## glareshield, short range, off in daylight) lights the panel face, yoke and pilot's lap.
## The gauge quads are unshaded (Cockpit), so the dimmer scales their colour; in daylight
## the multiplier is 1 and the panel looks exactly as before.

const FLOOD_COLOR := Color(1.0, 0.86, 0.68)

var _gauges: Array[StandardMaterial3D] = []
var _displays: Array[StandardMaterial3D] = []
var _flood: SpotLight3D
var _last := -1.0


## quads: [[MeshInstance3D, Rect2]] from Cockpit; display_rects: rects of light-emitting displays.
func setup(quads: Array, display_rects: Array, eye: Vector3) -> void:
	for q in quads:
		var m := (q[0] as MeshInstance3D).material_override as StandardMaterial3D
		if m == null:
			continue
		if (q[1] as Rect2) in display_rects:
			_displays.append(m)
		else:
			_gauges.append(m)
	_flood = SpotLight3D.new()
	var at := eye + Vector3(0.2, -0.02, -0.4)  # under the glareshield lip, aimed down at the panel
	_flood.transform = Transform3D(Basis.looking_at(Vector3(0.0, -0.43, -0.35), Vector3.UP), at)
	add_child(_flood)
	_flood.light_color = FLOOD_COLOR
	_flood.spot_range = 1.4
	_flood.spot_angle = 60.0
	_flood.spot_angle_attenuation = 1.2
	_flood.spot_attenuation = 1.2
	_flood.light_specular = 0.1
	_flood.light_cull_mask = 0xFFFFF & ~LightLogic.AIRCRAFT_LAYER
	_flood.shadow_enabled = false
	_flood.visible = false


func _process(_dt: float) -> void:
	var night := LightLogic.night_factor(Props.get_f("environment/sun_elev_deg", 30.0))
	var dim := Props.get_f("controls/lights/panel", LightLogic.PANEL_NIGHT_DEFAULT)
	var pw := Props.get_b("systems/electrical/powered", true)
	var key := night * 10.0 + dim * 1000.0 + (0.5 if pw else 0.0)
	if is_equal_approx(key, _last):
		return
	_last = key
	var g := LightLogic.panel_brightness(dim, night, pw)
	var d := LightLogic.display_brightness(dim, night, pw)
	# post lights are slightly warm at night
	var gc := Color(g, g * lerpf(1.0, 0.95, night), g * lerpf(1.0, 0.86, night))
	for m in _gauges:
		m.albedo_color = gc
	for m in _displays:
		m.albedo_color = Color(d, d, d)
	_flood.light_energy = LightLogic.flood_energy(dim, night, pw)
	_flood.visible = _flood.light_energy > 0.01
