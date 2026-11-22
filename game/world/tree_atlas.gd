class_name TreeAtlas
extends Node
## Bakes the hemi-octahedral impostor atlas (docs/GRAPHICS-PLAN.md G8) from the LOD1 tree meshes: every species seen
## from TreeOcta.N x N directions, the outer ring of frames being side views and the middle the view from above.
## One orthographic render in a private 3D world per pass (tree_bake.gdshader: 0 albedo + cover, 1 normal + foliage
## flag): each frame is an instance of the species' mesh turned to face the camera from that frame's direction.
## Each result is copied to an ImageTexture with mipmaps (a viewport texture has none: far trees would shimmer), then
## the viewport is freed. Emits `baked`. Headless runs have no renderer: they get a flat placeholder at once.
## Layout: species blocks side by side, each N x N frames of frame_px; frame (i, j) of species s is at column s * N + i,
## row j. frame_px comes from the preset (TreeQuality): 64 px = 2560 x 512, 96 px = 3840 x 768. Albedo is RGBA8, the
## normal RG8; both are block-compressed at bake time where the renderer supports it (compress()).
## sphere[s] (canonical crown centre xyz, radius w) tells tree.gdshader how each frame maps onto the tree.

signal baked(albedo: Texture2D, normal: Texture2D)

const N := TreeOcta.N

var albedo: Texture2D
var normal: Texture2D
var ready_ok := false
var busy := false
var frame_px := 0  # of the last bake
var sphere := PackedVector4Array()
var half := PackedVector4Array()  # half extents of the canonical box around each sphere centre (tree.gdshader quad size)
var mem_bytes := 0  # GPU memory of both textures with mipmaps, as uploaded
var compressed := false


## Canonical bounding sphere (centre xyz, radius w) of a unit mesh scaled by (aspect, 1, aspect), around its box centre.
static func bounds(m: ArrayMesh, aspect: float) -> Vector4:
	var verts: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sq := Vector3(aspect, 1.0, aspect)
	var box := AABB(verts[0] * sq, Vector3.ZERO)
	for p in verts:
		box = box.expand(p * sq)
	var c := box.get_center()
	var r := 0.0
	for p in verts:
		r = maxf(r, (p * sq).distance_to(c))
	return Vector4(c.x, c.y, c.z, r * 1.02)


## Half extents (xyz) of the canonical box of a unit mesh scaled by (aspect, 1, aspect), around `centre`.
static func half_extents(m: ArrayMesh, aspect: float, centre: Vector4) -> Vector4:
	var verts: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var c := Vector3(centre.x, centre.y, centre.z)
	var h := Vector3.ZERO
	for p in verts:
		h = h.max(((p * Vector3(aspect, 1.0, aspect)) - c).abs())
	return Vector4(h.x, h.y, h.z, 0.0) * 1.04


## GPU block compression where the renderer can sample it (BC3 / BC5 on desktop GPUs, ETC2 elsewhere); the image is
## returned unchanged if no compressor is available in this build, so the atlas always works.
static func compress(img: Image, is_normal: bool) -> Image:
	var mode := -1
	if RenderingServer.has_os_feature("s3tc"):
		mode = Image.COMPRESS_S3TC
	elif RenderingServer.has_os_feature("etc2"):
		mode = Image.COMPRESS_ETC2
	if mode < 0:
		return img
	var c := img.duplicate() as Image
	var src := Image.COMPRESS_SOURCE_NORMAL if is_normal else Image.COMPRESS_SOURCE_GENERIC
	if c.compress(mode, src) == OK and c.is_compressed():
		return c
	return img


static func atlas_size(px: int) -> Vector2i:
	return Vector2i(TreeSpecies.COUNT * N, N) * px


static func pixel_count(px: int) -> int:
	var s := atlas_size(px)
	return s.x * s.y


## Bake-world transform of frame (i, j) of a species (cell one unit wide, camera looking along -z).
static func frame_xform(sp: int, i: int, j: int, s: Vector4, aspect: float) -> Transform3D:
	var d := TreeOcta.frame_dir(i, j)
	var ax: Array = TreeOcta.basis(d)
	# canonical -> image axes (right, up, towards the camera), one frame = 2 x radius
	var rows := Basis.from_scale(Vector3.ONE / (2.0 * s.w)) * Basis(ax[0], ax[1], d).transposed()
	var cell := Vector3(sp * N + i + 0.5, -(j + 0.5), 0.0)
	return Transform3D(rows * Basis.from_scale(Vector3(aspect, 1.0, aspect)), cell - rows * Vector3(s.x, s.y, s.z))


func bake(px: int) -> void:
	if busy:
		return
	busy = true
	frame_px = px
	sphere.clear()
	half.clear()
	for sp in TreeSpecies.COUNT:
		var m := TreeMeshes.get_mesh(sp, 1)
		sphere.append(bounds(m, TreeSpecies.ASPECT[sp]))
		half.append(half_extents(m, TreeSpecies.ASPECT[sp], sphere[sp]))
	if DisplayServer.get_name() == "headless":
		var img := Image.create(TreeSpecies.COUNT * N * 2, N * 2, true, Image.FORMAT_RGBA8)
		img.fill(Color(0.1, 0.2, 0.07, 1.0))
		var nimg := Image.create(TreeSpecies.COUNT * N * 2, N * 2, true, Image.FORMAT_RGBA8)
		nimg.fill(Color(0.5, 0.5, 1.0, 1.0))
		_finish(ImageTexture.create_from_image(img), ImageTexture.create_from_image(nimg))
		return
	mem_bytes = 0
	var vp := SubViewport.new()
	vp.size = atlas_size(px)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = 1.0
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = N
	cam.near = 0.05
	cam.far = 20.0
	cam.position = Vector3(TreeSpecies.COUNT * N * 0.5, -N * 0.5, 5.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	vp.add_child(cam)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://world/tree_bake.gdshader")
	mat.set_shader_parameter("leaf_tex", preload("res://world/textures/trees/leaf_cards.png"))
	mat.set_shader_parameter("srgb_target", RenderingServer.get_current_rendering_method() != "gl_compatibility")
	for sp in TreeSpecies.COUNT:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = TreeMeshes.get_mesh(sp, 1)
		mm.instance_count = N * N
		for j in N:
			for i in N:
				mm.set_instance_transform(j * N + i, frame_xform(sp, i, j, sphere[sp], TreeSpecies.ASPECT[sp]))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vp.add_child(mi)
	add_child(vp)
	var tex: Array[Texture2D] = []
	for pass_id in 2:
		mat.set_shader_parameter("pass_id", pass_id)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8 if pass_id == 0 else Image.FORMAT_RG8)  # normals: x, y only (2 bytes)
		img.generate_mipmaps()
		img = compress(img, pass_id == 1)
		compressed = img.is_compressed()
		mem_bytes += img.get_data_size()
		tex.append(ImageTexture.create_from_image(img))
	vp.queue_free()
	_finish(tex[0], tex[1])


func _finish(a: Texture2D, n: Texture2D) -> void:
	albedo = a
	normal = n
	ready_ok = true
	busy = false
	baked.emit(a, n)


## The impostor quad (UV 0..1; tree.gdshader places its corners). Its culling box covers any species' bounding sphere
## in unit tree space (x and z in crown widths, so the slim trees need the most).
static func quad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_uv(uv[i])
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3(uv[i].x - 0.5, 1.0 - uv[i].y, 0.0))
	var m := st.commit()
	m.custom_aabb = AABB(Vector3(-2.2, -0.4, -2.2), Vector3(4.4, 1.8, 4.4))
	return m
