class_name AircraftHero
extends VBoxContainer
## The big picture on the aircraft page: the chosen aircraft's preview.jpg with rounded corners and,
## under it, the full name with its category. Without a picture only the dark panel remains.

const HEIGHT := 150.0

var _pic: TextureRect
var _title: Label
var _sub: Label


func _init() -> void:
	add_theme_constant_override("separation", 8)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, HEIGHT)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW  # rounded corners for the picture
	frame.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.03, 0.05, 0.08, 1.0), 14, Color(0, 0, 0, 0), 0.0))
	add_child(frame)
	_pic = TextureRect.new()
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(_pic)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	row.add_child(_title)
	_sub = Label.new()
	_sub.size_flags_horizontal = SIZE_EXPAND_FILL
	_sub.size_flags_vertical = SIZE_SHRINK_END
	_sub.clip_text = true
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sub.add_theme_font_size_override("font_size", 14)
	_sub.add_theme_color_override("font_color", MenuTheme.DIM)
	row.add_child(_sub)


func show_aircraft(j: Dictionary) -> void:
	_pic.texture = AircraftDef.load_def(str(j.get("id", ""))).preview()
	_title.text = str(j.get("name", ""))
	_sub.text = str(j.get("category", ""))
