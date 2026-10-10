extends Node
## Debug: show the controls page as the start screen would (glass panel right of the
## 200 px page nav) and the in-flight overlay, saving $FREESIM_SHOTS/controls_page.png
## and controls_overlay.png (default user://), then quit.


func _ready() -> void:
	var out := OS.get_environment("FREESIM_SHOTS")
	if out == "":
		out = OS.get_user_data_dir()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = MenuTheme.make()
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var panel := PanelContainer.new()  # start screen: 28 margin + 200 nav + 16 gap; top bar / FLY bar
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 244
	panel.offset_right = -28
	panel.offset_top = 100
	panel.offset_bottom = -110
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var stack := MarginContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("margin_right", 12)
	scroll.add_child(stack)
	var page := HBoxContainer.new()
	page.set_script(load("res://ui/menu/controls_page.gd"))
	stack.add_child(page)
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(out.path_join("controls_page.png"))
	page._start_capture("throttle")  # waiting state
	scroll.scroll_vertical = 2000
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(out.path_join("controls_page_end.png"))
	root.queue_free()
	var ov := CanvasLayer.new()
	ov.set_script(load("res://ui/controls_overlay.gd"))
	add_child(ov)
	ov.toggle()
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(out.path_join("controls_overlay.png"))
	get_tree().quit()
