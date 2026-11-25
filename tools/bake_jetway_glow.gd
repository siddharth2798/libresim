extends SceneTree
## Bakes the lit parts of the generic jetway's texture (game/world/models/vehicles/jetway_generic.png). The atlas holds the
## day skin in its top half and a night skin in the bottom half (lit cab windows, door, signs). The glow map keeps only what
## the night skin adds over the day skin, at the day skin's own UV, so jetway.gdshader can use it as emission:
##   ~/.local/bin/godot --headless --audio-driver Dummy --path game -s res://../tools/bake_jetway_glow.gd
## (run from the repo root; writes game/world/models/vehicles/jetway_glow.png, 512 x 256). A hand edit is not needed.

const SRC := "res://world/models/vehicles/jetway_generic.png"
const OUT := "res://world/models/vehicles/jetway_glow.png"
const KEEP := 0.45  # how much of the day skin's brightness the night skin must beat to count as light
const MIN_GLOW := 0.22  # weaker differences are shading, not lamps
const MIN_WARM := 0.2  # lamps here are warm (red over blue by this much); a grey difference is a different print


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height() / 2
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGB8)
	var lit := 0
	for y in h:
		for x in w:
			var d := img.get_pixel(x, y)
			var n := img.get_pixel(x, y + h)
			var g := Color(maxf(n.r - d.r * KEEP, 0.0), maxf(n.g - d.g * KEEP, 0.0), maxf(n.b - d.b * KEEP, 0.0))
			var m := (g.r + g.g + g.b) / 3.0
			if m < MIN_GLOW or g.r - g.b < MIN_WARM:
				g = Color.BLACK
			else:
				lit += 1
			out.set_pixel(x, y, g)
	out.save_png(ProjectSettings.globalize_path(OUT))
	print("lit texels: %d of %d" % [lit, w * h])
	quit()
