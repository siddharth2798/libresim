class_name RunwayNoise
extends RefCounted
## Value-noise lattice for world/runway_v2.gdshader: SIZE x SIZE random bytes, wrapping, bilinear. One texture fetch
## replaces the four hashes of an ALU value noise (rw_noise in runway_surface.gdshaderinc), which is what keeps the
## runway's many noise layers cheap. Fixed seed: every run and every runway reads the same lattice.

const SIZE := 256
static var _tex: ImageTexture


static func texture() -> ImageTexture:
	if _tex == null:
		_tex = ImageTexture.create_from_image(image())
	return _tex


static func image() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1729
	var data := PackedByteArray()
	data.resize(SIZE * SIZE)
	for i in data.size():
		data[i] = rng.randi() & 0xFF
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_L8, data)
	img.generate_mipmaps()
	return img
