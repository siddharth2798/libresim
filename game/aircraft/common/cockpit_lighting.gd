class_name CockpitLighting
extends Node3D
## Cockpit night lighting. C172S: internally lit instruments and the engine strip follow
## the PANEL dimmer (controls/lights/panel, 0..1) on bus power; the radio stack displays
## are light-emitting and stay readable; a warm glareshield flood (shadowless spot under the
## glareshield, short range, off in daylight) lights the panel face, yoke and pilot's lap.
## The gauge quads are unshaded (Cockpit), so the dimmer scales their colour; in daylight
## the multiplier is 1 and the panel looks exactly as before.
## A320 (materials from MaterialFinish): leather and glareshield roughness, a small night
## emission on the legend textures, and no glareshield flood (it would wash the displays).

const FLOOD_COLOR := Color(1.0, 0.86, 0.68)

var _gauges: Array[StandardMaterial3D] = []
var _displays: Array[StandardMaterial3D] = []
var _legends: Array[StandardMaterial3D] = []
var _flood: SpotLight3D
var _last := -1.0
var _deck := false  # A320 legend backlight is on; the glareshield flood stays off


## quads: [[MeshInstance3D, Rect2]] from Cockpit; display_rects: rects of light-emitting displays.
func setup(quads: Array, display_rects: Array, eye: Vector3, aircraft_id := "") -> void:
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
	_bind_deck(aircraft_id)


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
	if _deck:
		var e := MaterialFinish.legend_energy(night, dim, pw)
		for m in _legends:
			m.emission_energy_multiplier = e
			m.emission_enabled = e > 0.001
		_flood.light_energy = 0.0
		_flood.visible = false
	else:
		_flood.light_energy = LightLogic.flood_energy(dim, night, pw)
		_flood.visible = _flood.light_energy > 0.01


## Leather, glareshield and the windscreen from MaterialFinish; legend textures emit at night.
func _bind_deck(aircraft_id: String) -> void:
	if MaterialFinish.table(aircraft_id).is_empty():
		return
	var cockpit := get_parent() as Cockpit
	if cockpit == null or cockpit.interior == null:
		return
	var root: Node = cockpit.interior
	MaterialFinish.stamp_surfaces(root, aircraft_id, false)
	var want: Array = MaterialFinish.legend_names()
	var made := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mesh_mat := mesh.surface_get_material(i)
			var src_name := mesh_mat.resource_name if mesh_mat != null else ""
			if not want.has(src_name):
				continue
			var inst := mi as MeshInstance3D
			if made.has(src_name):
				inst.set_surface_override_material(i, made[src_name])
				continue
			var active := inst.get_active_material(i)
			var base: StandardMaterial3D = null
			if active is StandardMaterial3D:
				base = active
			elif mesh_mat is StandardMaterial3D:
				base = mesh_mat
			if base == null:
				continue
			var d := base.duplicate() as StandardMaterial3D
			d.resource_name = src_name
			d.emission_enabled = false
			d.emission = Color(1.0, 0.96, 0.88)
			d.emission_texture = d.albedo_texture
			d.emission_energy_multiplier = 0.0
			made[src_name] = d
			_legends.append(d)
			inst.set_surface_override_material(i, d)
	_deck = not _legends.is_empty()
