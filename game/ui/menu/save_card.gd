class_name SaveCard
extends Button
## One saved flight in the Saved flights list: a small picture, the name and a line with airport, aircraft and date.
## A toggle Button (the page puts the cards in one ButtonGroup). `activated` is a double click, or Enter / Space on
## a card that is already selected: it means "fly this one". The children are laid over the button (a Button does
## not lay out children), so the card has a fixed height.

signal activated

var meta := {}


func setup(m: Dictionary, thumb: Texture2D) -> SaveCard:
	meta = m
	custom_minimum_size = Vector2(0, 70)
	tooltip_text = SavesLogic.title(m)
	clip_contents = true
	PageStyles.card_item(self, 8.0, 6.0)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 8.0
	hb.offset_right = -8.0
	hb.offset_top = 6.0
	hb.offset_bottom = -6.0
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(90, 0)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture = thumb
	pic.clip_contents = true
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(pic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(col)
	var name_l := _line(col, SavesLogic.title(m), MenuTheme.TEXT, MenuTheme.SIZE_BODY)
	MenuTheme.use_font(name_l, "semibold")
	_line(col, SavesLogic.subline(m), MenuTheme.DIM, MenuTheme.SIZE_NOTE - 1)
	return self


func _line(parent: Control, text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and e.double_click:
		activated.emit()
	elif button_pressed and e.is_action_pressed("ui_accept") and not e.is_echo():
		activated.emit()
		accept_event()
