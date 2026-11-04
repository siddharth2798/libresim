class_name MotionBlurEffect
extends PfComputeEffect
## Motion blur as a CompositorEffect (Godot has none built in): motion_blur.glsl into a scratch image, then
## pf_copy.glsl back into the color buffer. Post-transparent, so the cloud quad is blurred too; before TAA and
## tonemapping (HDR, so bright lights streak properly).
## Forward+ only (PostFxRules.FX): it needs the velocity buffer (needs_motion_vectors); Mobile has no motion
## vectors, and camera-only blur there would also blur the moving aircraft wrong, so it stays off.
## Discontinuities: the driver (post_fx_driver.gd) sets reset on a floating-origin shift or a camera view switch;
## this effect also detects jumps itself (PostFxRules.is_cut, e.g. the fly-by camera re-placing). On those frames
## (PostFxRules.SKIP_FRAMES) nothing is blurred, because the renderer's previous transforms are stale.

const SHADER := "res://world/postfx/motion_blur.glsl"
const COPY := "res://world/postfx/pf_copy.glsl"
const FLIP_Y := true  # texel row 0 = top of the view (as world/sun_glare.gdshader finds); flip if the sky blurs mirrored

## Written by the driver on the main thread, read here on the render thread (plain values, a frame late at most).
var shutter := PostFxRules.SHUTTER
var max_px := PostFxRules.MAX_BLUR_PX
var samples := PostFxRules.BLUR_SAMPLES
var near_cut := 20.0  # m, PostFxRules.near_cutoff_m
var frame_dt := 1.0 / 60.0
var reset := false

var _prev_xf := Transform3D()
var _prev_proj := Projection()
var _has_prev := false
var _skip := 0
var _ubo := RID()


func _init() -> void:
	super._init()
	needs_motion_vectors = true


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or device() == null:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers == null or scene == null:
		return
	var xf := scene.get_cam_transform()
	var proj := scene.get_cam_projection()
	var cut := _has_prev and PostFxRules.is_cut(_prev_xf, xf, frame_dt)
	_skip = PostFxRules.next_skip(_skip, reset or not _has_prev, cut)
	reset = false
	var prev_xf := _prev_xf
	var prev_proj := _prev_proj
	_prev_xf = xf
	_prev_proj = proj
	_has_prev = true
	var scale := PostFxRules.blur_scale(shutter, frame_dt)
	if _skip > 0 or scale <= 0.0:
		return
	var color := buffers.get_color_layer(0)
	if color_version(color) != "fp16":
		_fail("motion blur needs an RGBA16F storage color buffer (Forward+)")
		return
	var blur := pipeline(SHADER)
	var copy := pipeline(COPY)
	if blur.is_empty() or copy.is_empty():
		return
	var size := buffers.get_internal_size()
	var depth := buffers.get_depth_layer(0)
	var vel := buffers.get_velocity_layer(0)
	var has_vel := sampleable(vel)
	if not sampleable(depth):
		_fail("motion blur needs a sampleable depth buffer")
		return
	var temp := scratch(buffers, &"mb_temp", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size)
	_update_ubo(proj.inverse(), prev_proj * Projection(prev_xf.affine_inverse() * xf))
	var lin := sampler(true)
	var near := sampler(false)
	dispatch(blur, [u_sampled(0, lin, color), u_sampled(1, near, depth), u_sampled(2, near, vel if has_vel else depth),
		u_image(3, temp), u_buffer(4, _ubo)],
		PackedFloat32Array([size.x, size.y, scale, max_px, samples, near_cut, 1.0 if has_vel else 0.0, 1.0 if FLIP_Y else 0.0]), size)
	dispatch(copy, [u_image(0, temp), u_image(1, color)], PackedFloat32Array([size.x, size.y, 0.0, 0.0]), size)


func _update_ubo(inv_proj: Projection, to_prev: Projection) -> void:
	var data := mat_floats(inv_proj)
	data.append_array(mat_floats(to_prev))
	var bytes := data.to_byte_array()
	if not _ubo.is_valid():
		_ubo = own(rd.uniform_buffer_create(bytes.size(), bytes))
	else:
		rd.buffer_update(_ubo, 0, bytes.size(), bytes)

