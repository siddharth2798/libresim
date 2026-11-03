class_name PfComputeEffect
extends CompositorEffect
## Shared plumbing for the compute-shader post effects (motion blur, sun shafts): shader + pipeline creation on
## the render thread, a linear clamp sampler, per-viewport scratch textures and a uniform-set helper.
## Everything is created lazily inside _render_callback, because the RenderingDevice only exists there; under the
## headless dummy renderer RenderingServer.get_rendering_device() is null and the effect simply does nothing.

const CTX := &"libresim_postfx"

var rd: RenderingDevice
var _shaders := {}  # key -> [shader RID, pipeline RID]
var _samplers := {}  # linear: bool -> sampler RID
var _owned: Array[RID] = []  # buffers made by a subclass (own()), freed with the effect
var _failed := false  # a shader did not compile, or the color buffer cannot be written: stay off
var _warned := false


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true


## The RenderingDevice, or null (dummy renderer, or a shader failed). Call first in _render_callback.
func device() -> RenderingDevice:
	if _failed:
		return null
	if rd == null:
		rd = RenderingServer.get_rendering_device()
	return rd


## Compute pipeline for `path` (an imported .glsl, RDShaderFile) and its `version` ("" = the default one).
func pipeline(path: String, version := "") -> Array:
	var key := path + ":" + version
	if _shaders.has(key):
		return _shaders[key]
	var file := load(path) as RDShaderFile
	var spirv: RDShaderSPIRV = file.get_spirv(StringName(version)) if file else null
	if spirv == null or spirv.compile_error_compute != "":
		_fail("shader %s (%s) did not compile: %s" % [path, version, spirv.compile_error_compute if spirv else "missing"])
		return []
	var shader := rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		_fail("shader %s could not be created" % path)
		return []
	var out := [shader, rd.compute_pipeline_create(shader)]
	_shaders[key] = out
	return out


## Clamp-to-edge sampler; nearest for depth and velocity (depth formats need not support linear filtering).
func sampler(linear := true) -> RID:
	if not _samplers.has(linear):
		var s := RDSamplerState.new()
		var f := RenderingDevice.SAMPLER_FILTER_LINEAR if linear else RenderingDevice.SAMPLER_FILTER_NEAREST
		s.min_filter = f
		s.mag_filter = f
		s.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		s.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		_samplers[linear] = rd.sampler_create(s)
	return _samplers[linear]


## A scratch texture in the viewport's buffers (re-made by Godot when the viewport is resized).
func scratch(buffers: RenderSceneBuffersRD, name: StringName, format: int, size: Vector2i) -> RID:
	if buffers.has_texture(CTX, name):
		var f: RDTextureFormat = buffers.get_texture_format(CTX, name)
		if f.width == size.x and f.height == size.y and f.format == format:
			return buffers.get_texture(CTX, name)
		buffers.clear_context(CTX)  # size changed: drop the whole context, the others are re-made on demand
	var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	return buffers.create_texture(CTX, name, format, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)


## "fp16" (Forward+ RGBA16F), "rgb10" (Mobile A2B10G10R10) or "" when the color buffer cannot be a storage image.
func color_version(color: RID) -> String:
	var f := rd.texture_get_format(color)
	if f == null or (f.usage_bits & RenderingDevice.TEXTURE_USAGE_STORAGE_BIT) == 0:
		return ""
	match f.format:
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
			return "fp16"
		RenderingDevice.DATA_FORMAT_A2B10G10R10_UNORM_PACK32:
			return "rgb10"
	return ""


## The texture exists and can be bound as a sampled texture (Mobile may keep depth as a transient attachment).
func sampleable(tex: RID) -> bool:
	if not tex.is_valid():
		return false
	var f := rd.texture_get_format(tex)
	return f != null and (f.usage_bits & RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT) != 0


static func u_sampled(binding: int, smp: RID, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(smp)
	u.add_id(tex)
	return u


static func u_image(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u


static func u_buffer(binding: int, buf: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u.binding = binding
	u.add_id(buf)
	return u


## One compute dispatch over `size` pixels (8x8 groups) with uniforms in set 0 and a push constant.
func dispatch(pipe: Array, uniforms: Array, push: PackedFloat32Array, size: Vector2i) -> void:
	var set_rid := UniformSetCacheRD.get_cache(pipe[0], 0, uniforms)
	var bytes := push.to_byte_array()
	bytes.resize(ceili(bytes.size() / 16.0) * 16)  # push constants are padded to 16 bytes
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipe[1])
	rd.compute_list_bind_uniform_set(list, set_rid, 0)
	rd.compute_list_set_push_constant(list, bytes, bytes.size())
	rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	rd.compute_list_end()


## Column-major floats of a Projection for a std140 mat4.
static func mat_floats(p: Projection) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for c in [p.x, p.y, p.z, p.w]:
		out.append_array([c.x, c.y, c.z, c.w])
	return out


func _fail(msg: String) -> void:
	_failed = true
	if not _warned:
		_warned = true
		push_warning("PostFx: %s; the effect is off" % msg)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		for k in _shaders:
			if _shaders[k][0].is_valid():
				rd.free_rid(_shaders[k][0])  # frees its pipeline and cached uniform sets too
		for k in _samplers:
			rd.free_rid(_samplers[k])
		for r in _owned:
			if r.is_valid():
				rd.free_rid(r)


## Keep a RenderingDevice resource for the effect's lifetime (only this base class frees: GDScript calls
## _notification on every script of the chain, so a subclass override would free twice).
func own(r: RID) -> RID:
	_owned.append(r)
	return r
