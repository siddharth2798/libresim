class_name SunShaftsEffect
extends PfComputeEffect
## Screen-space sun shafts ("god rays", sun_shafts.glsl): a quarter-resolution mask of bright open sky around the
## sun, then a 32-tap radial blur towards the sun added to the color buffer in place. Post-transparent, so the
## cloud quad occludes. Runs on Forward+ and, if its color buffer is a storage image (checked at run time:
## color_version), on Mobile. Strength, sun direction and colour come from the driver (PostFxLook.shafts_strength).

const SHADER := "res://world/postfx/sun_shafts.glsl"
const THRESHOLD := 1.0  # HDR sky luminance that counts as bright (the glow threshold in flight.tscn is 1.2)
const SAMPLES := 32

## Written by the driver on the main thread.
var sun_dir := Vector3.UP  # render frame, towards the sun
var sun_color := Color(1.0, 0.92, 0.8)
var strength := 0.0  # 0 = skipped entirely (no passes)


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or strength <= 0.001 or device() == null:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers == null or scene == null:
		return
	var xf := scene.get_cam_transform()
	var sv := xf.basis.inverse() * sun_dir
	if sv.z > -0.05:  # the sun is behind the camera
		return
	var clip := scene.get_cam_projection() * Vector4(sv.x, sv.y, sv.z, 0.0)
	var sun_uv := Vector2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5)
	if sun_uv.x < -0.6 or sun_uv.x > 1.6 or sun_uv.y < -0.6 or sun_uv.y > 1.6:
		return
	var color := buffers.get_color_layer(0)
	var ver := color_version(color)
	if ver == "":
		_fail("sun shafts need a storage color buffer (RGBA16F or RGB10A2)")
		return
	var depth := buffers.get_depth_layer(0)
	if not sampleable(depth):
		_fail("sun shafts need a sampleable depth buffer")
		return
	var mask_pipe := pipeline(SHADER, "mask")
	var comp_pipe := pipeline(SHADER, "comp_" + ver)
	if mask_pipe.is_empty() or comp_pipe.is_empty():
		return
	var size := buffers.get_internal_size()
	var msize := Vector2i(maxi(size.x / 4, 1), maxi(size.y / 4, 1))
	var mask := scratch(buffers, &"shaft_mask", RenderingDevice.DATA_FORMAT_R16_SFLOAT, msize)
	var lum_scale := 0.5 if ver == "rgb10" else 1.0
	var aspect := float(size.x) / maxf(size.y, 1.0)
	var c := sun_color
	var params := func(s: Vector2i) -> PackedFloat32Array:
		return PackedFloat32Array([s.x, s.y, sun_uv.x, sun_uv.y, c.r, c.g, c.b, strength, THRESHOLD, lum_scale, aspect, SAMPLES])
	dispatch(mask_pipe, [u_sampled(0, sampler(true), color), u_sampled(1, sampler(false), depth),
		u_image(2, mask)], params.call(msize), msize)
	dispatch(comp_pipe, [u_sampled(0, sampler(true), mask), u_image(1, color)], params.call(size), size)
