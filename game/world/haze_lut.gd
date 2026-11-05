class_name HazeLut
extends RefCounted
## View-dependent far-haze colour (docs/GRAPHICS-PLAN.md G4): a small RGBAH texture over (angle between view and sun azimuth,
## 0..180 deg; view elevation above the dipped horizon, sine 0..S_MAX on a square-root scale) holding the clear-sky colour of
## the analytic sky (Atmosphere.sky + the sky shader's sun glow), read by world/haze_sky.gdshaderinc in the terrain / building /
## tree / cloud haze. It depends only on sun elevation and aerosol, so SkyTime refills it when those change (0.25 deg of sun,
## ~1 min of sim time), one row per frame (32 Atmosphere.sky calls, ~1 ms) into a back image uploaded when complete; the first
## fill is immediate. Globals: haze_lut, haze_sun, haze_ref (project.godot).

const W := 32
const H := 8
const S_MAX := 0.5  # sine of the top row's elevation (30 deg)
const EL_STEP := 0.25  # deg of sun elevation per refill
const LUM_MAX := 4.0  # HDR cap (the sky itself is not capped; this only guards against blow-ups)

var img := Image.create(W, H, false, Image.FORMAT_RGBAH)
var tex: ImageTexture
var _back := Image.create(W, H, false, Image.FORMAT_RGBAH)
var _key := Vector2i(1 << 30, 0)
var _row := H  # next row of the back image to fill (H = idle)
var _job := []  # [sun, aerosol, gain, glow] of the fill in progress
var _published := false


## Direction (render frame) of texel (i, j) for a sun at `sun` (unit, render frame), with no horizon dip.
static func texel_dir(i: int, j: int, sun: Vector3) -> Vector3:
	var a := PI * float(i) / float(W - 1)
	var s := S_MAX * pow(float(j) / float(H - 1), 2.0)
	var h := Vector2(sun.x, sun.z)
	h = h.normalized() if h.length() > 1e-4 else Vector2(0.0, -1.0)
	h = h.rotated(a) * sqrt(1.0 - s * s)
	return Vector3(h.x, s, h.y)


## CPU twin of haze_color()'s texture coordinate for a view direction (render frame, unit).
static func lut_uv(dir: Vector3, sun: Vector3, dip_sin: float) -> Vector2:
	var hz := Vector2(dir.x, dir.z)
	var sh := Vector2(sun.x, sun.z)
	sh = sh.normalized() if sh.length() > 1e-4 else Vector2(0.0, -1.0)
	var ca := hz.normalized().dot(sh) if hz.length() > 1e-4 else 1.0
	var a := acos(clampf(ca, -1.0, 1.0)) / PI
	var v := sqrt(clampf((dir.y + dip_sin) / S_MAX, 0.0, 1.0))
	return Vector2((a * (W - 1) + 0.5) / W, (v * (H - 1) + 0.5) / H)


## The sky shader's sun glow (without the disc) towards dir, for a glow colour = LIGHT0_COLOR x energy x day.
static func glow_at(dir: Vector3, sun: Vector3, glow: Color) -> Color:
	var mu := maxf(dir.dot(sun), 0.0)
	return glow * (pow(mu, 12.0) * 0.18 + pow(mu, 3.0) * 0.06)


## Clear-sky haze colour (linear) of texel (i, j).
static func texel_color(i: int, j: int, sun: Vector3, aerosol: float, gain: float, glow: Color) -> Color:
	var d := texel_dir(i, j, sun)
	var c := Atmosphere.sky(d, sun, aerosol, gain) + glow_at(d, sun, glow)
	var lum := c.get_luminance()
	if lum > LUM_MAX:
		c *= LUM_MAX / lum
	c.a = 1.0
	return c


## Called by SkyTime each frame. sun: towards the sun (render frame); ref: the linear model colour fog_color was
## built from; clear: weight of the clear sky (1 - overcast); dip_sin: sine of the horizon dip at the camera.
func update(sun: Vector3, el_deg: float, aerosol: float, glow: Color, ref: Color, clear: float, dip_sin: float) -> void:
	var key := Vector2i(roundi(el_deg / EL_STEP), roundi(aerosol * 10.0))
	if key != _key:
		_key = key
		_job = [sun.normalized(), aerosol, Atmosphere.twilight_gain(el_deg), glow]
		_row = 0
		if tex == null:  # first fill: all rows now
			_fill_rows(H)
	if _row < H:
		_fill_rows(1)
	var sh := Vector2(sun.x, sun.z)
	sh = sh.normalized() if sh.length() > 1e-4 else Vector2(0.0, -1.0)
	RenderingServer.global_shader_parameter_set("haze_sun", Vector4(sh.x, sh.y, dip_sin, clampf(clear, 0.0, 1.0)))
	RenderingServer.global_shader_parameter_set("haze_ref", Vector3(ref.r, ref.g, ref.b))
	if not _published and tex != null:
		_published = true
		RenderingServer.global_shader_parameter_set("haze_lut", tex)


func _fill_rows(n: int) -> void:
	var sun: Vector3 = _job[0]
	for _k in n:
		if _row >= H:
			break
		for i in W:
			_back.set_pixel(i, _row, texel_color(i, _row, sun, _job[1], _job[2], _job[3]))
		_row += 1
	if _row < H:
		return
	img.copy_from(_back)
	if tex == null:
		tex = ImageTexture.create_from_image(img)
	else:
		tex.update(img)


## Sine of the dip of the sea horizon seen from altitude alt_m (m above sea level) over the curved ground of
## curvature.gdshaderinc (drop d^2 / 2R): the ray at depression t grazes it where tan(t)^2 = 2 h / R.
static func horizon_dip_sin(alt_m: float) -> float:
	return sin(atan(sqrt(2.0 * maxf(alt_m, 0.0) / Atmosphere.RE)))
