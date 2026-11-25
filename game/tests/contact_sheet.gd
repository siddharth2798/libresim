extends SceneTree
## Tool: a contact sheet of numbered frames. godot --headless --audio-driver Dummy --path game --script res://tests/contact_sheet.gd -- dir=<abs dir> tag=before out=<abs png> [from=0] [to=47] [cols=8] [step=1]
## Each cell is the frame scaled to 240 px wide, labelled with its number.


func _init() -> void:
	var a := {"from": "0", "to": "47", "cols": "8", "step": "1", "tag": "before"}
	for s in OS.get_cmdline_user_args():
		if s.contains("="):
			a[s.get_slice("=", 0)] = s.get_slice("=", 1)
	var frames: Array = []
	var names: Array = []  # file=<tag>:<n>,<n>;<tag>:<n>... : chosen frames of one or more sequences, in that order
	if a.has("pick"):
		for part in str(a.pick).split(";"):
			for n in part.get_slice(":", 1).split(","):
				names.append([part.get_slice(":", 0), int(n)])
	else:
		for i in range(int(a.from), int(a.to) + 1, int(a.step)):
			names.append([a.tag, i])
	for nm in names:
		var i: int = nm[1]
		var p: String = str(a.dir).path_join(("%s_%02d.png" % [nm[0], i]) if not a.has("pat") else str(a.pat) % i)
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			img.convert(Image.FORMAT_RGB8)
			var w := 240
			img.resize(w, int(w * img.get_height() / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
			frames.append([i, img])
	if frames.is_empty():
		print("no frames")
		quit(1)
		return
	var cw: int = frames[0][1].get_width()
	var ch: int = frames[0][1].get_height()
	var cols := int(a.cols)
	var rows := ceili(frames.size() / float(cols))
	var sheet := Image.create(cw * cols, ch * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	var font := ThemeDB.fallback_font
	for k in frames.size():
		var img: Image = frames[k][1]
		sheet.blit_rect(img, Rect2i(0, 0, cw, ch), Vector2i((k % cols) * cw, (k / cols) * ch))
		# a number as little 3x5 pixel digits in the corner
		_digits(sheet, str(frames[k][0]), Vector2i((k % cols) * cw + 3, (k / cols) * ch + 3))
	sheet.save_png(str(a.out))
	print("saved ", a.out, " ", frames.size(), " frames")
	quit()


const GLYPHS := {
	"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111", "4": "101101111001001",
	"5": "111100111001111", "6": "111100111101111", "7": "111001001001001", "8": "111101111101111", "9": "111101111001111",
}


func _digits(img: Image, s: String, at: Vector2i) -> void:
	var x := at.x
	for ch in s:
		var g: String = GLYPHS[ch]
		for i in 15:
			if g[i] == "1":
				var px := x + (i % 3) * 2
				var py := at.y + (i / 3) * 2
				for dx in 2:
					for dy in 2:
						img.set_pixel(px + dx, py + dy, Color(1, 1, 0))
		x += 8
