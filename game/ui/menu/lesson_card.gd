class_name LessonCard
extends Button
## One lesson of the Training page's list: its number and title, and under it the stars you earned (amber) or
## "not flown yet" with the time. A toggle Button (the page puts the cards in one ButtonGroup). The two lines are
## Labels laid over the button (a Button does not lay out children), so the card has a fixed height.

var _stars := Label.new()
var _rest := Label.new()


func setup(index: int, lesson: Dictionary, stars: int) -> LessonCard:
	custom_minimum_size = Vector2(0, 60)
	PageStyles.card_item(self, 14.0, 8.0)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 14.0
	col.offset_right = -10.0
	col.offset_top = 6.0
	col.offset_bottom = -6.0
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var title := Label.new()
	title.text = "%d   %s" % [index + 1, lesson.title]
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.use_font(title, "semibold", 18)
	col.add_child(title)
	var sub := HBoxContainer.new()
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_theme_constant_override("separation", 6)
	col.add_child(sub)
	var pad := Control.new()  # under the title, past the number
	pad.custom_minimum_size = Vector2(26, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_child(pad)
	for l in [_stars, _rest]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", MenuTheme.SIZE_NOTE)
		sub.add_child(l)
	_rest.add_theme_color_override("font_color", MenuTheme.DIM)
	set_stars(stars, int(lesson.get("minutes", 5)))
	return self


func set_stars(stars: int, minutes: int) -> void:
	_stars.text = PageStyles.stars_text(stars)
	_stars.add_theme_color_override("font_color", MenuTheme.WARN if stars > 0 else MenuTheme.DIM)
	_rest.text = "·  about %d min" % minutes
