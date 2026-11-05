extends Node
## Debug: focus-ring screenshots of the main controls (rail entry, chip, Segmented, SwitchRow, tab, search box, buttons, home card
## and link). Each control gets the focus, the window is captured and a crop around it is saved; a contact sheet
## (focus_sheet.png) puts them side by side. Needs a display; scratch data only.
##   FREESIM_SIZE=1280x720  FREESIM_SHOTS=<dir>  FREESIM_TAG=<prefix>

var _s: Control
var _out := ""
var _crops: Array[Image] = []
var _names: Array[String] = []


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	get_window().always_on_top = true
	Session.skip_menu = false
	Session.interactive_override = 0
	Session.save_path = "user://_focus_last_flight.json"
	TrainingLogic.save_path = "user://_focus_training.json"
	SituationStore.dir = "user://_focus_saves/"
	Session.setup = Session.DEFAULT.duplicate(true)
	_out = OS.get_environment("FREESIM_SHOTS") if OS.get_environment("FREESIM_SHOTS") != "" else OS.get_user_data_dir()
	await get_tree().process_frame
	_s = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_s)
	await get_tree().create_timer(0.8).timeout
	var home: Control = _s.screen("home")
	await _grab("home card", home._cards[0])
	await _grab("home link", home._more[1])
	_s.go("flight")
	var f: Control = _s.screen("flight")
	f.show_step(0)
	await _grab("rail entry", f.rail.entries[1])
	await _grab("footer chip", f.chips.get_child(0))
	await _grab("Back", f.back_btn)
	await _grab("Next", f.primary_btn)
	await _grab("Fly now", f.fly_btn)
	f.show_step(5)
	var rec: Control = f.pages[5]
	for c in _all(rec):
		if c is Segmented:
			await _grab("Segmented", (c as Segmented).get_child(1))
			break
	for c in _all(rec):
		if c is SwitchRow:
			await _grab("SwitchRow", c)
			break
	_s.go("controls")
	var cp: Control = _s.screen("controls").pages[0]
	await _grab("Controls tab", cp.tabs.button("keyboard"))
	await _grab("search box", cp.search)
	await _grab("aircraft switch", cp.aircraft_switch.get_child(0))
	_s.go("options")
	var op: Control = _s.screen("options").pages[0]
	op.tabs.select("display")
	await _grab("Options tab", op.tabs.button("display"))
	for c in _all(op.tabs.page("display")):
		if c is SwitchRow:
			await _grab("Options switch", c)
			break
	_sheet()
	get_tree().quit()


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for k in n.get_children():
		out.append(k)
		out.append_array(_all(k))
	return out


func _grab(name: String, c: Control) -> void:
	c.grab_focus()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var k := float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var r := c.get_global_rect().grow(12.0)
	r.size.x = minf(r.size.x, 460.0)  # a wide row: only its left part
	var px := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	_crops.append(img.get_region(px))
	_names.append(name)
	print("FOCUS %s focused=%s rect=%s" % [name, c.has_focus(), c.get_global_rect()])


func _sheet() -> void:
	var w := 0
	var h := 0
	for i in _crops:
		w = maxi(w, i.get_width())
		h += i.get_height() + 6
	var cols := 2
	var col_h := (h + cols - 1) / cols
	var sheet := Image.create(w * cols + 12, col_h + 400, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.12, 0.16))
	var y := [0, 0]
	for n in _crops.size():
		var col := 0 if y[0] <= y[1] else 1
		sheet.blit_rect(_crops[n], Rect2i(Vector2i.ZERO, _crops[n].get_size()), Vector2i(col * (w + 12), y[col]))
		y[col] += _crops[n].get_height() + 6
	sheet = sheet.get_region(Rect2i(0, 0, sheet.get_width(), maxi(y[0], y[1])))
	sheet.save_png(_out.path_join("%sfocus_sheet.png" % OS.get_environment("FREESIM_TAG")))
