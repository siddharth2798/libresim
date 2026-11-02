class_name Cockpit
extends Node3D
## 3D cockpit. With the aircraft's interior glb (def.path("interior"), e.g. the FlightGear c172p
## interior, GPL-2.0-or-later) and spots, the live gauges from the InstrumentPanel SubViewport are
## mapped onto small quads at the real instrument positions; otherwise a placeholder panel quad +
## frame is used. Mouse clicks on any gauge quad are forwarded to the SubViewport (knobs work).
## Child of AircraftModel (local: -Z nose, +Y up, origin = CG).
## aircraft.json "cockpit":
##   eye         [x, y, z] pilot eye in the glb's model frame (x aft, y right, z up from the model origin)
##   panel_mesh  name of the gauge panel's mesh node (round gauges are lifted clear of its bezels)
##   spots       {item name: {"pos": [x,y,z] model frame, "size": face width m, "round": bool, "screen": name, "item": panel item}}
##   screens     {name: {centre, width, height, u_dir, v_dir, normal}} glass displays measured on the glb (model
##               frame, m). A spot whose item (or "screen") names one gets a quad of exactly that size and tilt
##               (the display is stretched to the glass); other spots are upright quads of "size" wide.
##   levers      {pivot: {drive, map, ...}} moving controls of the interior glb (cockpit_levers.gd); absent = static
## Item names are the InstrumentPanel ones (panel.json): gauges, "radios", "strip", "switches".

const REFRESH := 1.0 / 30.0
const FACE_GAP := 0.0015  # gauge quads sit this far in front of the panel's frontmost surface (m)

var viewport: SubViewport
var panel_ui: InstrumentPanel
var eye := Vector3.ZERO  # local, for the camera
var interior: Node3D
var levers: CockpitLevers  # moving controls (aircraft.json cockpit.levers), null on a static cockpit
var _quads: Array = []  # [MeshInstance3D, Rect2 panel px]
var _acc := 0.0
var _panel_mesh := ""
var _frame := StandardMaterial3D.new()


func build(model: AircraftModel, fallback_eye: Vector3) -> void:
	var def := model.def
	var cfg := def.section("cockpit")
	viewport = SubViewport.new()
	viewport.size = Vector2i(InstrumentPanel.natural_size())
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	panel_ui = InstrumentPanel.new()
	panel_ui.size = InstrumentPanel.natural_size()
	viewport.add_child(panel_ui)
	var rects := InstrumentPanel.rects()
	var spots: Dictionary = cfg.get("spots", {})
	_panel_mesh = str(cfg.get("panel_mesh", ""))
	eye = fallback_eye
	if ResourceLoader.exists(def.path("interior")):
		interior = (load(def.path("interior")) as PackedScene).instantiate()
		interior.transform = model.fg_transform()
		add_child(interior)
		AircraftModel.fix_glass(interior)
		if cfg.has("eye"):
			eye = model.fg_to_local(_vec(cfg.eye))
		if cfg.get("levers") is Dictionary:
			levers = CockpitLevers.new()
			add_child(levers)
			levers.build(interior, cfg.levers)
	if interior != null and not spots.is_empty():
		var front := _panel_front()
		for k in spots:
			var item := str(spots[k].get("item", k))  # "item": the panel item a second spot (the first officer's) shows
			if not rects.has(item):
				continue
			var r: Rect2 = rects[item]
			var w: float = spots[k].size
			var pos := model.fg_to_local(_vec(spots[k].pos)) + Vector3(0, 0, 0.004)
			var s := 1.0
			if spots[k].get("round", false) and not is_nan(front) and front + FACE_GAP > pos.z:
				# the panel's bezels stand proud of the nominal face plane and would clip the gauge:
				# lift the quad clear of them and shrink it so it looks the same size from the eye
				var lifted := Vector3(pos.x, pos.y, front + FACE_GAP)
				s = (eye - lifted).length() / (eye - pos).length()
				pos = lifted
			var sc = cfg.get("screens", {}).get(str(spots[k].get("screen", k)))
			if sc is Dictionary:
				var u := _dir(sc.u_dir)
				var v := _dir(sc.v_dir)
				var n := _dir(sc.normal)
				_add_quad(model.fg_to_local(_vec(sc.centre)) + n * 0.003, Vector2(sc.width, sc.height), r, Basis(u, v, n))
				continue
			_add_quad(pos, Vector2(w, w * r.size.y / r.size.x) * s, r, Basis())
	else:
		_build_placeholder(fallback_eye)
	var lighting := CockpitLighting.new()
	add_child(lighting)
	lighting.setup(_quads, [rects["radios"]] if interior != null and not spots.is_empty() and rects.has("radios") else [], eye)


## A model-frame direction (x aft, y right, z up) in the aircraft's local frame (x right, y up, z aft).
func _dir(a: Array) -> Vector3:
	return Vector3(a[1], a[2], a[0])


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Local z of the frontmost (toward the pilot) point of the gauge panel mesh, NAN if there is none.
func _panel_front() -> float:
	var best := NAN
	if _panel_mesh == "":
		return NAN
	for mi in interior.find_children(_panel_mesh, "MeshInstance3D", true, false):
		var t: Transform3D = (mi as MeshInstance3D).transform
		var p := mi.get_parent()
		while p != null and p != interior:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		var z := (interior.transform * t * (mi as MeshInstance3D).get_aabb()).end.z
		best = z if is_nan(best) else maxf(best, z)
	return best


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
		if str(Props.get_v("view/mode", "")) == "Cockpit":  # the 3D panel is only seen from inside
			panel_ui.refresh()
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
