extends SceneTree
## Render an SVG to a PNG with Godot's own SVG loader (used by tools/branding/make_logo.py).
##   godot --headless --path game -s res://branding/rasterize.gd -- in.svg out.png [scale]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var svg := FileAccess.get_file_as_string(a[0])
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(a[2]) if a.size() > 2 else 1.0)
	if err != OK:
		push_error("svg load failed: %d" % err)
		quit(1)
		return
	img.save_png(a[1])
	quit()
