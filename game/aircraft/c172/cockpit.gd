class_name Cockpit
extends Node3D
## 3D cockpit. With models/interior.glb (FlightGear c172p interior, GPL-2.0-or-later)
## the live gauges from the InstrumentPanel SubViewport are mapped onto small quads
## at the real instrument positions; otherwise a placeholder panel quad + frame is used.
## Mouse clicks on any gauge quad are forwarded to the SubViewport (knobs work).
## Child of C172Model (local: -Z nose, +Y up, origin = CG).

const REFRESH := 1.0 / 30.0
const INTERIOR := "res://aircraft/c172/models/interior.glb"
## FlightGear model-frame centres (x aft, y right, z up) + face size (m) per panel item.
const SPOTS := {
	"asi": [Vector3(-0.364, -0.3115, 0.129), 0.080],
	"ai": [Vector3(-0.364, -0.2215, 0.1286), 0.080],
	"alt": [Vector3(-0.363, -0.1324, 0.1303), 0.080],
	"tc": [Vector3(-0.365, -0.3111, 0.0293), 0.080],
	"hi": [Vector3(-0.365, -0.2216, 0.0289), 0.080],
	"vsi": [Vector3(-0.3656, -0.1324, 0.0284), 0.080],
	"tach": [Vector3(-0.3636, -0.3119, -0.0787), 0.076],
	"strip": [Vector3(-0.362, 0.33, 0.06), 0.15],
	"switches": [Vector3(-0.352, -0.19, -0.168), 0.40],
}
## Pilot eye in the FlightGear model frame (left seat).
const EYE_FG := Vector3(0.33, -0.22, 0.31)

var viewport: SubViewport
var panel_ui: InstrumentPanel
var eye := Vector3.ZERO  # local, for the camera
var interior: Node3D
var _quads: Array = []  # [MeshInstance3D, Rect2 panel px]
var _acc := 0.0
var _frame := StandardMaterial3D.new()


func build(model: C172Model, fallback_eye: Vector3) -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(InstrumentPanel.natural_size())
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	panel_ui = InstrumentPanel.new()
	panel_ui.size = InstrumentPanel.natural_size()
	viewport.add_child(panel_ui)
	if ResourceLoader.exists(INTERIOR):
		interior = (load(INTERIOR) as PackedScene).instantiate()
		interior.transform = model.fg_transform()
		add_child(interior)
		C172Model.fix_glass(interior)
		var rects := InstrumentPanel.rects()
		for k in SPOTS:
			var r: Rect2 = rects[k]
			var w: float = SPOTS[k][1]
			_add_quad(model.fg_to_local(SPOTS[k][0]) + Vector3(0, 0, 0.004), Vector2(w, w * r.size.y / r.size.x), r, Basis())
		eye = model.fg_to_local(EYE_FG)
	else:
		_build_placeholder(fallback_eye)
		eye = fallback_eye


func _add_quad(pos: Vector3, size: Vector2, r: Rect2, b: Basis) -> void:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = viewport.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var vs := InstrumentPanel.natural_size()
	m.uv1_offset = Vector3(r.position.x / vs.x, r.position.y / vs.y, 0)
	m.uv1_scale = Vector3(r.size.x / vs.x, r.size.y / vs.y, 1)
	mi.material_override = m
	mi.transform = Transform3D(b, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_quads.append([mi, r])


func _build_placeholder(e: Vector3) -> void:
	var vs := InstrumentPanel.natural_size()
	var w := 1.05
	_add_quad(e + Vector3(0.12, -0.27, -0.72), Vector2(w, w * vs.y / vs.x), Rect2(Vector2.ZERO, vs), Basis(Vector3.RIGHT, deg_to_rad(-12.0)))
	_frame.albedo_color = Color(0.11, 0.11, 0.12)
	_box(e + Vector3(0.0, -0.27 + 0.22 + 0.04, -0.82), Vector3(1.3, 0.06, 0.32))
	for s in [-1.0, 1.0]:
		_box(e + Vector3(s * 0.56, 0.12, -0.78), Vector3(0.05, 0.75, 0.05), Vector3(0, 0, s * -0.35))


func _box(p: Vector3, s: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	mi.mesh = b
	mi.material_override = _frame
	mi.position = p
	mi.rotation = rot
	add_child(mi)


func _process(dt: float) -> void:
	_acc += dt
	if _acc >= REFRESH:
		_acc = 0.0
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(global_position) < 4.0:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Forward a mouse event from the main viewport to the panel if it hits a gauge quad.
func forward_mouse(e: InputEventMouse, cam: Camera3D) -> bool:
	var from := cam.project_ray_origin(e.position)
	var dir := cam.project_ray_normal(e.position)
	for item in _quads:
		var mi: MeshInstance3D = item[0]
		var r: Rect2 = item[1]
		var xf := mi.global_transform
		var n := xf.basis.z.normalized()
		var denom := dir.dot(n)
		if absf(denom) < 1e-4:
			continue
		var t := (xf.origin - from).dot(n) / denom
		if t <= 0.0:
			continue
		var local := xf.affine_inverse() * (from + dir * t)
		var qs: Vector2 = (mi.mesh as QuadMesh).size
		var uv := Vector2(local.x / qs.x + 0.5, 0.5 - local.y / qs.y)
		if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
			continue
		var ev: InputEventMouse = e.duplicate()
		ev.position = r.position + uv * r.size
		ev.global_position = ev.position
		viewport.push_input(ev)
		return true
	return false
