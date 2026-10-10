class_name Cockpit
extends Node3D
## Placeholder 3D cockpit around the pilot eyepoint: instrument panel quad
## showing the InstrumentPanel SubViewport (redrawn at ~30 Hz), glare shield,
## window frames and roof. Mouse clicks on the panel are forwarded to the
## SubViewport, so gauge knobs work in the 3D cockpit.
## Child of C172Model (local frame: -Z nose, +Y up, origin = CG).

const PANEL_W := 1.05  # metres
const REFRESH := 1.0 / 30.0

var viewport: SubViewport
var panel_ui: InstrumentPanel
var _quad: MeshInstance3D
var _panel_xf: Transform3D  # local transform of the panel quad
var _acc := 0.0
var _frame := StandardMaterial3D.new()


func build(eye: Vector3) -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(InstrumentPanel.natural_size())
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.transparent_bg = false
	viewport.gui_disable_input = false
	add_child(viewport)
	panel_ui = InstrumentPanel.new()
	panel_ui.size = InstrumentPanel.natural_size()
	viewport.add_child(panel_ui)

	var aspect := InstrumentPanel.natural_size().y / InstrumentPanel.natural_size().x
	var q := QuadMesh.new()
	q.size = Vector2(PANEL_W, PANEL_W * aspect)
	_quad = MeshInstance3D.new()
	_quad.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = viewport.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_quad.material_override = m
	# panel ~0.7 m ahead of and 0.25 m below the eye, tilted back 12 deg
	_panel_xf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), eye + Vector3(0.12, -0.27, -0.72))
	_quad.transform = _panel_xf
	add_child(_quad)

	_frame.albedo_color = Color(0.11, 0.11, 0.12)
	_frame.roughness = 0.9
	var h: float = q.size.y
	_box(eye + Vector3(0.0, -0.27 + h * 0.5 + 0.04, -0.82), Vector3(1.3, 0.06, 0.32))  # glare shield
	_box(eye + Vector3(0.0, -0.27 - h * 0.5 - 0.15, -0.74), Vector3(1.3, 0.3, 0.1))  # lower panel
	for s in [-1.0, 1.0]:
		_box(eye + Vector3(s * 0.56, 0.12, -0.78), Vector3(0.05, 0.75, 0.05), Vector3(0, 0, s * -0.35))  # A-pillars
		_box(eye + Vector3(s * 0.6, -0.33, 0.0), Vector3(0.05, 0.12, 1.6))  # door sills
		_box(eye + Vector3(s * 0.6, 0.18, 0.05), Vector3(0.05, 0.6, 0.06))  # door posts
	_box(eye + Vector3(0.0, 0.32, -0.15), Vector3(1.2, 0.04, 1.2))  # headliner (wing root above)


func _box(p: Vector3, s: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	mi.mesh = b
	mi.material_override = _frame
	mi.position = p
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(dt: float) -> void:
	_acc += dt
	if _acc >= REFRESH and visible:
		_acc = 0.0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Forward a mouse event from the main viewport to the panel, if the ray hits it.
func forward_mouse(e: InputEventMouse, cam: Camera3D) -> bool:
	var from := cam.project_ray_origin(e.position)
	var dir := cam.project_ray_normal(e.position)
	var xf := global_transform * _panel_xf
	var n := xf.basis.z.normalized()
	var denom := dir.dot(n)
	if absf(denom) < 1e-4:
		return false
	var t := (xf.origin - from).dot(n) / denom
	if t <= 0.0:
		return false
	var local := xf.affine_inverse() * (from + dir * t)
	var qs: Vector2 = (_quad.mesh as QuadMesh).size
	var uv := Vector2(local.x / qs.x + 0.5, 0.5 - local.y / qs.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return false
	var ev: InputEventMouse = e.duplicate()
	ev.position = uv * Vector2(viewport.size)
	ev.global_position = ev.position
	viewport.push_input(ev)
	return true
