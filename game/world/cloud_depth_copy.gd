class_name CloudDepthCopy
extends PfComputeEffect
## Copies the opaque depth buffer into an R32F Texture2DRD after the opaque pass, so the low-resolution
## cloud march (a SubViewport, which has no scene depth of its own) can stop at terrain and the aircraft.
## The copy is one frame behind the picture: SubViewports draw before the main view. CloudUpscale sharpens
## the upscale with the current depth on the main camera. Headless (no RenderingDevice) leaves `published` empty
## and the clouds stay on the full-resolution path.

const SHADER := "res://world/cloud_depth_copy.glsl"
## 0: copied texels line up with SCREEN_UV. 1: sample with v flipped. See the shader header.
const FLIP := 0.0

var published: Texture2DRD
var _rid: RID
var _size := Vector2i.ZERO


func _init() -> void:
	super._init()
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE
	access_resolved_color = false
	access_resolved_depth = true
	published = Texture2DRD.new()


## The copied depth, or null until the first successful copy (and whenever the device has no depth).
func texture() -> Texture2DRD:
	if _failed or published == null or not published.texture_rd_rid.is_valid():
		return null
	return published


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_OPAQUE or device() == null:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var depth := buffers.get_depth_layer(0)
	if not sampleable(depth):
		return
	var size := buffers.get_internal_size()
	if size.x < 2 or size.y < 2:
		return
	var pipe := pipeline(SHADER)
	if pipe.is_empty():
		return
	var dst := _image(size)
	if not dst.is_valid():
		return
	dispatch(pipe, [u_sampled(0, sampler(false), depth), u_image(1, dst)],
		PackedFloat32Array([size.x, size.y, 0.0, 0.0]), size)


func _image(size: Vector2i) -> RID:
	if _rid.is_valid() and _size == size:
		return _rid
	var fmt := RDTextureFormat.new()
	fmt.width = size.x
	fmt.height = size.y
	fmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var created := rd.texture_create(fmt, RDTextureView.new())
	if not created.is_valid():
		_fail("cloud depth copy could not allocate an R32F image")
		return RID()
	var old := _rid
	_rid = created
	_size = size
	published.texture_rd_rid = _rid
	if old.is_valid():
		rd.free_rid(old)
	return _rid


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rid.is_valid() and rd != null:
		published.texture_rd_rid = RID()
		rd.free_rid(_rid)
		_rid = RID()
