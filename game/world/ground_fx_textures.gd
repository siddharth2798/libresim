class_name GroundFxTextures
extends RefCounted
## Sprite pictures of the ground particle effects (GroundFxLook), made once at run time (white, shape in the alpha).
##   mist    2 x 2 atlas of soft, irregular, noise-shaped wisps (domain-warped value noise inside a broad falloff that is
##           exactly 0 well inside the square: no round edge, no disc). Each particle picks one frame at random and turns
##           at random, so overlapping sprites read as mist, spray or dust, not as a pile of balls
##   streak  one soft streak, long along the quad's Y and thin across, broken up along its length: the rooster tail's
##           sheet of droplets, drawn upright and stretched along the flight of the droplets
##   crown   a tiny crown of droplets above a thin flat ring: a raindrop splash

const FRAME := 64  # px per mist frame

static var _cache := {}


static func mist() -> Texture2D:
	if not _cache.has("mist"):
		var img := Image.create(FRAME * 2, FRAME * 2, false, Image.FORMAT_RGBA8)
		for f in 4:
			_wisp(img, (f % 2) * FRAME, (f / 2) * FRAME, 3.1 + 17.3 * f)
		img.generate_mipmaps()
		_cache["mist"] = ImageTexture.create_from_image(img)
	return _cache["mist"]


static func streak() -> Texture2D:
	if not _cache.has("streak"):
		var w := 32
		var h := 128
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var u := (x + 0.5) / w * 2.0 - 1.0
				var v := (y + 0.5) / h * 2.0 - 1.0
				var n := _fbm(u * 2.0 + 5.0, v * 7.0 + 1.0)
				var across := 1.0 - smoothstep(0.15, 1.0, absf(u) * (0.75 + 0.5 * n))
				var along := 1.0 - smoothstep(0.35, 1.0, absf(v))
				var a := across * along * (0.35 + 0.65 * smoothstep(0.3, 0.75, n))
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
		img.generate_mipmaps()
		_cache["streak"] = ImageTexture.create_from_image(img)
	return _cache["streak"]


static func crown() -> Texture2D:
	if not _cache.has("crown"):
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		_dot(img, Vector2(0.5, 0.88), 0.34, 0.45, 0.25)
		for i in 7:  # bold enough to survive the mipmaps of a sprite a few pixels wide
			var a := lerpf(-1.2, 1.2, (i + rng.randf() * 0.5) / 7.0)
			var r := rng.randf_range(0.22, 0.4)
			_dot(img, Vector2(0.5 + sin(a) * r, 0.88 - cos(a) * r * 1.5), rng.randf_range(0.06, 0.1), 0.9)
		img.generate_mipmaps()
		_cache["crown"] = ImageTexture.create_from_image(img)
	return _cache["crown"]


## One mist frame at pixel (ox, oy): warped noise, thresholded softly, inside an irregular falloff that ends at r 0.8-1.
static func _wisp(img: Image, ox: int, oy: int, seed: float) -> void:
	for y in FRAME:
		for x in FRAME:
			var vx := (x + 0.5) / FRAME * 2.0 - 1.0
			var vy := (y + 0.5) / FRAME * 2.0 - 1.0
			var qx := vx * 2.2 + seed
			var qy := vy * 2.2 - seed * 0.7
			var wx := qx + 0.9 * _fbm(qx + 1.7, qy + 9.2)
			var wy := qy + 0.9 * _fbm(qx + 8.3, qy + 2.8)
			var n := _fbm(wx, wy)
			var r := sqrt(vx * vx + vy * vy)
			var lobe := _fbm(vx * 1.3 - seed, vy * 1.3 + seed * 0.4)  # a slow wobble of the outline: lobes, not a disc
			var fall := (1.0 - smoothstep(0.05, 0.95, r * (0.55 + 1.0 * lobe))) * (1.0 - smoothstep(0.8, 1.0, r))
			var a := fall * (0.2 + 0.8 * smoothstep(0.3, 0.75, n))
			img.set_pixel(ox + x, oy + y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))


static func _fbm(x: float, y: float) -> float:
	return _vn(x, y) * 0.55 + _vn(x * 2.03 + 5.2, y * 2.03 + 1.3) * 0.3 + _vn(x * 4.1 + 2.9, y * 4.1 + 7.7) * 0.15


static func _vn(x: float, y: float) -> float:
	var xi := floorf(x)
	var yi := floorf(y)
	var fx := x - xi
	var fy := y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(_h(xi, yi), _h(xi + 1.0, yi), fx), lerpf(_h(xi, yi + 1.0), _h(xi + 1.0, yi + 1.0), fx), fy)


static func _h(a: float, b: float) -> float:
	var s := sin(a * 127.1 + b * 311.7) * 43758.5453
	return s - floorf(s)


## Adds a soft round dot (centre and radius in 0..1 of the image, y squashed by sy) to the alpha.
static func _dot(img: Image, c: Vector2, r: float, a: float, sy := 1.0) -> void:
	var n := img.get_width()
	for y in n:
		for x in n:
			var d := Vector2((x + 0.5) / n - c.x, ((y + 0.5) / n - c.y) / sy).length() / r
			if d < 1.0:
				var px := img.get_pixel(x, y)
				px.a = clampf(px.a + a * pow(1.0 - d * d, 2.0), 0.0, 1.0)
				img.set_pixel(x, y, px)
