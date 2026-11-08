class_name CloudUpscale
extends Node
## Half (high band) or quarter (max) resolution cloud march, history blend and a depth-aware upscale (G7).
## Child of CloudLayer. The march reuses volumetric_clouds.gdshader in a small view; cloud_upscale.gdshader
## reprojects the previous frame and sharpens edges on the main camera. Scale 1 leaves CloudLayer's mesh
## drawing, with use_scene_depth and march_jitter forced off, so Low and Medium do not change.
## sync() is deferred from CloudLayer.update_layer so it runs after the camera has moved, before the view draws.

var layer: CloudLayer
var _cam: Camera3D
var _depth: CloudDepthCopy
var _march: SubViewport
var _hist: Array[SubViewport] = []
var _accum_mi: MeshInstance3D
var _blit: MeshInstance3D
var _accum_mat: ShaderMaterial
var _blit_mat: ShaderMaterial
var _write := 0
var _frame := 0
var _has_prev := false
var _prev_xf: Transform3D
var _prev_proj: Projection


func bind(host: CloudLayer) -> void:
	layer = host


func sync() -> void:
	if layer == null or not is_inside_tree():
		return
	var cam: Camera3D = layer.get_parent() as Camera3D
	if cam == null:
		return
	_cam = cam
	var scale := CloudTemporal.scale_for_steps(layer.steps)
	var show := layer.cover > 0.01 and layer.steps > 0
	if not show or scale <= 1:
		_show_full()
		_use_effect(cam, false)
		return
	_use_effect(cam, true)
	var depth: Texture2DRD = null
	if _depth != null:
		depth = _depth.texture()
	if depth == null or depth.get_width() < 2 or depth.get_height() < 2:
		_show_full()
		return
	_temporal(cam, scale, Vector2i(depth.get_width(), depth.get_height()), depth)


func _exit_tree() -> void:
	if _cam != null and is_instance_valid(_cam):
		_use_effect(_cam, false)


func _show_full() -> void:
	_has_prev = false
	if layer != null:
		layer.set_screen_draw(true)
		layer._mat.set_shader_parameter("use_scene_depth", 0.0)
		layer._mat.set_shader_parameter("march_jitter", Vector2.ZERO)
	if _blit != null:
		_blit.visible = false
	_pause(_march)
	for vp in _hist:
		_pause(vp)


func _temporal(cam: Camera3D, scale: int, full: Vector2i, depth: Texture2DRD) -> void:
	var low := Vector2i(maxi(int(float(full.x) / float(scale)), 1), maxi(int(float(full.y) / float(scale)), 1))
	_ensure(full, low)
	_march.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_match(cam, _march)
	for vp in _hist:
		_match(cam, vp)
	layer.set_screen_draw(false)
	_blit.visible = true
	layer._mat.set_shader_parameter("use_scene_depth", 1.0)
	layer._mat.set_shader_parameter("march_jitter", CloudTemporal.march_jitter(_frame, scale, Vector2(full)))
	layer._mat.set_shader_parameter("depth_flip", CloudDepthCopy.FLIP)
	layer._mat.set_shader_parameter("scene_depth", depth)
	_frame += 1
	var reset := _has_prev and CloudTemporal.is_camera_cut(_prev_xf, cam.global_transform)
	var bw := CloudTemporal.blend_weight(reset or not _has_prev, scale)
	var reproj := Projection()
	if _has_prev:
		reproj = CloudTemporal.reproj_matrix(_prev_xf, _prev_proj, cam.global_transform)
	_prev_xf = cam.global_transform
	_prev_proj = cam.get_camera_projection()
	var inv_proj := _prev_proj.inverse()
	_has_prev = true
	var dest: SubViewport = _hist[_write]
	var hist: SubViewport = _hist[1 - _write]
	_pause(hist)
	dest.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_place_accum(dest)
	_accum_mat.set_shader_parameter("blit", 0.0)
	_accum_mat.set_shader_parameter("block", scale)
	_accum_mat.set_shader_parameter("blend_w", bw)
	var hist_on := 0.0
	if bw < 0.999:
		hist_on = 1.0
	_accum_mat.set_shader_parameter("history_on", hist_on)
	_accum_mat.set_shader_parameter("depth_flip", CloudDepthCopy.FLIP)
	_accum_mat.set_shader_parameter("scene_depth", depth)
	_accum_mat.set_shader_parameter("current_tex", _march.get_texture())
	_accum_mat.set_shader_parameter("history_tex", hist.get_texture())
	_accum_mat.set_shader_parameter("reproj", reproj)
	_accum_mat.set_shader_parameter("inv_proj", inv_proj)
	_blit_mat.set_shader_parameter("inv_proj", inv_proj)
	_blit_mat.set_shader_parameter("blit", 1.0)
	_blit_mat.set_shader_parameter("block", scale)
	_blit_mat.set_shader_parameter("accum_tex", dest.get_texture())
	var thick = layer._mat.get_shader_parameter("cloud_thick")
	var clear := CloudTemporal.clear_dist(cam.global_position.y, layer.base, float(thick) if thick != null else 900.0)
	_accum_mat.set_shader_parameter("clear_m", clear)
	_blit_mat.set_shader_parameter("clear_m", clear)
	_write = 1 - _write


func _ensure(full: Vector2i, low: Vector2i) -> void:
	if _march == null:
		_accum_mat = ShaderMaterial.new()
		_accum_mat.shader = preload("res://world/cloud_upscale.gdshader")
		_blit_mat = ShaderMaterial.new()
		_blit_mat.shader = _accum_mat.shader
		_blit_mat.set_shader_parameter("blit", 1.0)
		_march = _make_vp()
		_march.add_child(_quad(layer._mat))
		_blit = _quad(_blit_mat)
		_blit.sorting_offset = 1000.0
		_blit.visible = false
		add_child(_blit)
		_hist.append(_make_vp())
		_hist.append(_make_vp())
		_accum_mi = _quad(_accum_mat)
	if _march.size != low:
		_march.size = low
	for vp in _hist:
		if vp.size != full:
			vp.size = full


func _place_accum(dest: SubViewport) -> void:
	var parent := _accum_mi.get_parent()
	if parent == dest:
		return
	if parent != null:
		parent.remove_child(_accum_mi)
	dest.add_child(_accum_mi)


func _make_vp() -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.gui_disable_input = true
	vp.handle_input_locally = false
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.scaling_3d_scale = 1.0
	vp.positional_shadow_atlas_size = 0
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(2, 2)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.name = "Cam"
	vp.add_child(cam)
	add_child(vp)
	cam.current = true
	return vp


func _quad(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	mi.material_override = mat
	mi.extra_cull_margin = 1.0e6
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


func _match(src: Camera3D, vp: SubViewport) -> void:
	var dst: Camera3D = vp.get_node("Cam") as Camera3D
	dst.projection = src.projection
	dst.fov = src.fov
	dst.near = src.near
	dst.far = src.far
	dst.keep_aspect = src.keep_aspect
	dst.h_offset = src.h_offset
	dst.v_offset = src.v_offset
	dst.global_transform = src.global_transform


func _pause(vp: SubViewport) -> void:
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _use_effect(cam: Camera3D, on: bool) -> void:
	if on and _depth == null:
		_depth = CloudDepthCopy.new()
	if _depth == null:
		return
	var we := _world_env(cam)
	if we == null:
		return
	var comp: Compositor = we.compositor
	if comp == null:
		if not on:
			return
		comp = Compositor.new()
		we.compositor = comp
	var list: Array = comp.compositor_effects
	var at := list.find(_depth)
	if on and at < 0:
		list.append(_depth)
		comp.compositor_effects = list
	elif not on and at >= 0:
		list.remove_at(at)
		comp.compositor_effects = list


func _world_env(from: Node) -> WorldEnvironment:
	var n: Node = from
	while n != null:
		var we: WorldEnvironment = n.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we != null:
			return we
		n = n.get_parent()
	return null
