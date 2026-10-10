extends Control
## Layout check for the start-screen Aircraft and Options pages at 1280x720:
##   godot --path game res://tests/debug_options.tscn   (needs a display)
## Saves aircraft_page{,_aft,_heavy}.png and options_page.png to $FREESIM_SHOTS
## (default /tmp) and quits. Each page sits in a 1008x480 panel like the start screen.

const PAGES := [["aircraft_page", "res://ui/menu/aircraft_page.gd"], ["options_page", "res://ui/menu/options_page.gd"]]


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	set_anchors_preset(PRESET_FULL_RECT)
	theme = MenuTheme.make()
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.13, 0.17)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	var out := OS.get_environment("FREESIM_SHOTS")
	if out.is_empty():
		out = "/tmp"
	for pg in PAGES:
		var panel := PanelContainer.new()
		panel.position = Vector2(244, 100)
		panel.size = Vector2(1008, 480)
		add_child(panel)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_right", 12)
		panel.add_child(m)
		var p: Control = HBoxContainer.new()
		p.set_script(load(pg[1]))
		p.size_flags_vertical = SIZE_EXPAND_FILL
		m.add_child(p)
		await _shot(out.path_join(pg[0] + ".png"))
		print("%s: panel %s, page min %s" % [pg[0], panel.size, p.get_combined_minimum_size()])
		if pg[0] == "aircraft_page":
			var keep := {}
			for k in ["fuel_gal", "copilot_kg", "rear_kg", "baggage_kg"]:
				keep[k] = Session.setup[k]
			p._sliders.rear_kg.value = 200.0
			p._sliders.baggage_kg.value = 54.0
			p._sliders.fuel_gal.value = 5.0
			await _shot(out.path_join("aircraft_page_aft.png"))
			print("aft: panel %s" % panel.size)
			p._sliders.copilot_kg.value = 110.0
			p._sliders.fuel_gal.value = 28.0
			await _shot(out.path_join("aircraft_page_heavy.png"))
			print("heavy: panel %s" % panel.size)
			for k in keep:
				Session.setup[k] = keep[k]
		panel.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _shot(path: String) -> void:
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
