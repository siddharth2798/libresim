class_name CloudLayer
extends MeshInstance3D
## Drives the full-screen volumetric cloud pass (volumetric_clouds.gdshader).
## Child of the camera. Noise textures are generated once (FastNoiseLite, seamless).
## The CPU copy of the density (for in-cloud fog) lives in SkyTime.cloud_density.

var steps := 24  # set by graphics presets
var _mat := ShaderMaterial.new()
var _lo: NoiseTexture2D
var _hi: NoiseTexture2D
var _img_lo: Image
var _img_hi: Image
var base := 1400.0
var cover := 0.0
var drift := Vector2.ZERO
var shadow := Vector4.ZERO  # last cloud_shadow global: (base m, coverage, strength, 0)


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mesh = q
	_mat.shader = preload("res://world/volumetric_clouds.gdshader")
	_lo = _noise(256, 0.012, 4, 1)
	_hi = _noise(256, 0.03, 3, 2)
	_lo.changed.connect(func(): _img_lo = _lo.get_image())
	_hi.changed.connect(func(): _img_hi = _hi.get_image())
	_mat.set_shader_parameter("noise_lo", _lo)
	_mat.set_shader_parameter("noise_hi", _hi)
	material_override = _mat
	extra_cull_margin = 1e6
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sorting_offset = 1000.0  # after other transparents


static func _noise(size: int, freq: float, octaves: int, seed: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	t.normalize = true
	t.noise = n
	return t


## Called by SkyTime each frame.
func update_layer(cam_world: Vector3, base_m: float, cov: float, dr: Vector2, sun_dir: Vector3, sun_col: Color, amb: Color, base_dark := 0.0) -> void:
	base = base_m
	cover = cov
	drift = dr
	visible = cover > 0.01 and steps > 0
	_mat.set_shader_parameter("cam_world", cam_world)
	_mat.set_shader_parameter("cloud_base", base)
	_mat.set_shader_parameter("coverage", cover)
	_mat.set_shader_parameter("wind_offset", drift)
	_mat.set_shader_parameter("sun_dir", sun_dir)
	_mat.set_shader_parameter("sun_color", sun_col)
	_mat.set_shader_parameter("ambient", amb)
	_mat.set_shader_parameter("steps", steps)
	_mat.set_shader_parameter("base_dark", base_dark)
	_publish_shadow(sun_dir, sun_col, base_dark)


## In-cloud presentation (CloudInside): k the in-cloud factor, pocket_m a radius around the camera kept free of
## cloud (outside views, so the aircraft is not washed out by the march), glow a soft light towards the sun.
func set_inside(k: float, pocket_m: float, glow: Color) -> void:
	_mat.set_shader_parameter("in_cloud", k)
	_mat.set_shader_parameter("clear_r", pocket_m)
	_mat.set_shader_parameter("glow_color", glow)
	_mat.set_shader_parameter("vert_grad", CloudLook.VERT)


## Cloud shadows on the ground (terrain.gdshader): the same coverage noise, projected along the sun.
func _publish_shadow(sun_dir: Vector3, sun_col: Color, base_dark: float) -> void:
	var st := clampf(sun_col.get_luminance() * 1.1, 0.0, 1.0) * clampf(cover * 3.0, 0.0, 1.0) \
		* (1.0 - clampf(base_dark * 2.0, 0.0, 1.0)) * (1.0 if steps > 0 else 0.0)
	var wb := FloatingOrigin.wrap_base_value()
	shadow = Vector4(base, cover, st, 0.0)
	RenderingServer.global_shader_parameter_set("cloud_shadow", shadow)
	RenderingServer.global_shader_parameter_set("cloud_uv_off", Vector2(fposmod(wb.x + drift.x, 9000.0), fposmod(wb.y + drift.y, 9000.0)) / 9000.0)
	RenderingServer.global_shader_parameter_set("cloud_sun", sun_dir.normalized())
	if _lo.get_image() != null:
		RenderingServer.global_shader_parameter_set("cloud_noise", _lo)


static func _sample(img: Image, uv: Vector2) -> float:
	if img == null:
		return 0.0
	var w := img.get_width()
	var x := fposmod(uv.x, 1.0) * w
	var y := fposmod(uv.y, 1.0) * w
	return img.get_pixel(int(x) % w, int(y) % w).r


## CPU copy of the shader's density() at world ENU p (for in-cloud fog / effects).
func density_at(p: Vector3) -> float:
	var h := (p.z - base) / 900.0
	if h < 0.0 or h > 1.0 or cover <= 0.0:
		return 0.0
	var q := (Vector2(p.x, p.y) + drift) / 9000.0
	var cov := _sample(_img_lo, q) - (1.0 - cover) * 0.82
	var dome := cov * 2.6 - h * h * 1.1 - (1.0 - smoothstep(0.0, 0.1, h)) * 0.4
	var detail := _sample(_img_hi, q * 6.0 + Vector2(h * 0.35, -h * 0.27))
	return clampf((dome - (1.0 - detail) * 0.32) * 2.2, 0.0, 1.0)
