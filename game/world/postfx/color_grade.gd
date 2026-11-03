class_name ColorGrade
extends RefCounted
## Time-of-day / weather colour grading on the Environment's adjustments (applied after tonemapping, every
## renderer): contrast and saturation from PostFxLook.grade, white balance through a small generated 3D LUT
## (adjustment_color_correction). Brightness stays 1: exposure belongs to the auto exposure (world/auto_exposure.gd),
## and contrast pivots on mid grey. The LUT is rebuilt only when the warmth moves by more than LUT_STEP.
## lut_override: an artist's 3D LUT (Texture3D) used instead of the generated one (the "LUT hook").

const LUT_SIZE := 17
const LUT_STEP := 0.02

static var lut_override: Texture3D = null

var _lut: ImageTexture3D
var _lut_warmth := INF


## The LUT images (LUT_SIZE slices) for a warmth (-1..1): identity times PostFxLook.warmth_gains.
static func lut_images(warmth: float) -> Array[Image]:
	var g := PostFxLook.warmth_gains(warmth)
	var out: Array[Image] = []
	var n := LUT_SIZE
	for z in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for y in n:
			for x in n:
				var c := Color(x / float(n - 1) * g.x, y / float(n - 1) * g.y, z / float(n - 1) * g.z)
				img.set_pixel(x, y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0)))
		out.append(img)
	return out


## on: the color_grading option (and preset rule); g: PostFxLook.grade(...).
func apply(env: Environment, on: bool, g: Dictionary) -> void:
	if env == null:
		return
	env.adjustment_enabled = on
	if not on:
		return
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = float(g.contrast)
	env.adjustment_saturation = float(g.saturation)
	if lut_override != null:
		env.adjustment_color_correction = lut_override
		return
	var w := float(g.warmth)
	if absf(w - _lut_warmth) >= LUT_STEP:
		_lut_warmth = w
		if _lut == null:
			_lut = ImageTexture3D.new()
			_lut.create(Image.FORMAT_RGB8, LUT_SIZE, LUT_SIZE, LUT_SIZE, false, lut_images(w))
		else:
			_lut.update(lut_images(w))
	env.adjustment_color_correction = _lut
