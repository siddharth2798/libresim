class_name FcuLcd
extends Node3D
## The A320 glareshield FCU's LCD strip in the 3D cockpit (aircraft.json cockpit.fcu_lcd): a transparent quad over the
## model's LCD windows, painted by FcuLcdDraw from FcuWindows (speed, heading, altitude, V/S, dashes and managed dots,
## SPD/MACH and HDG/TRK labels). The model's static label quads (always showing every label, dash and dot at once) are
## hidden. Backlit: unshaded, dimmed at night like the displays (LightLogic.display_brightness), blank without power.
##   centre, width, height, u_dir, v_dir, normal   the strip on the glb (FlightGear model frame, m), like cockpit.screens
##   px      [w, h] canvas pixels;  hide  {"mesh": node, "materials": [surface material names]}

const GAP := 0.0006

var viewport: SubViewport
var canvas: FcuLcdDraw
var quad: MeshInstance3D
var _mat: StandardMaterial3D
var _sig := ""
var _bright := -1.0


func build(model: AircraftModel, interior: Node, cfg: Dictionary) -> void:
	var px: Array = cfg.get("px", [1024, 70])
	viewport = SubViewport.new()
	viewport.size = Vector2i(int(px[0]), int(px[1]))
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	canvas = FcuLcdDraw.new()
	canvas.size = Vector2(viewport.size)
	viewport.add_child(canvas)
	var q := QuadMesh.new()
	q.size = Vector2(float(cfg.width), float(cfg.height))
	quad = MeshInstance3D.new()
	quad.name = "FcuLcd"
	quad.mesh = q
	_mat = StandardMaterial3D.new()
	_mat.albedo_texture = viewport.get_texture()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material_override = _mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var n := _dir(cfg.normal)
	quad.transform = Transform3D(Basis(_dir(cfg.u_dir), _dir(cfg.v_dir), n), model.fg_to_local(_vec(cfg.centre)) + n * GAP)
	add_child(quad)
	_hide(interior, cfg.get("hide", {}))


## The texts the strip shows now, to repaint only on a change.
static func signature() -> String:
	if not FcuWindows.powered():
		return ""
	return "%s|%s|%s|%s|%s" % [FcuWindows.spd(), FcuWindows.hdg(), FcuWindows.alt(), FcuWindows.vs(), FcuWindows.mode_label()]


func _process(_dt: float) -> void:
	if str(Props.get_v("view/mode", "")) != "Cockpit":
		return
	var sig := signature()
	if sig != _sig:
		_sig = sig
		canvas.queue_redraw()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var night := LightLogic.night_factor(Props.get_f("environment/sun_elev_deg", 30.0))
	var dim := Props.get_f("controls/lights/panel", LightLogic.PANEL_NIGHT_DEFAULT)
	var b := LightLogic.display_brightness(dim, night, Props.get_b("systems/electrical/powered", true))
	if not is_equal_approx(b, _bright):
		_bright = b
		_mat.albedo_color = Color(b, b, b)


func _hide(interior: Node, spec: Dictionary) -> void:
	var src := interior.find_child(str(spec.get("mesh", "")), true, false) as MeshInstance3D
	if src == null or src.mesh == null:
		return
	var clear := StandardMaterial3D.new()
	clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear.albedo_color = Color(0, 0, 0, 0)
	clear.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var names: Array = spec.get("materials", [])
	for i in src.mesh.get_surface_count():
		var m := src.mesh.surface_get_material(i)
		if m != null and m.resource_name in names:
			src.set_surface_override_material(i, clear)


## A FlightGear model-frame direction (x aft, y right, z up) in the aircraft's local frame (x right, y up, z aft).
static func _dir(a: Array) -> Vector3:
	return Vector3(float(a[1]), float(a[2]), float(a[0])).normalized()


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
