class_name SliderRow
extends HBoxContainer
## One compact setting on a single line: label, slider, value. Used by the weather and
## aircraft pages of the start screen. The page connects `slider.value_changed` and sets the
## value text (`value_label.text`) itself, because every setting formats its value differently.

var slider := HSlider.new()
var value_label := Label.new()
var _label := Label.new()


## `tip` (optional) is the hover text for the whole row.
func setup(label: String, lo: float, hi: float, step: float, tip := "", label_w := 130.0, value_w := 62.0) -> SliderRow:
	add_theme_constant_override("separation", 10)
	_label.text = label
	_label.custom_minimum_size = Vector2(label_w, 0)
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_label)
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(80, 0)
	add_child(slider)
	value_label.custom_minimum_size = Vector2(value_w, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(value_label)
	if tip != "":
		tip_on(_label, tip)
		slider.tooltip_text = tip
	return self


## Hover text on any control (labels ignore the mouse unless told otherwise).
static func tip_on(c: Control, tip: String) -> void:
	c.tooltip_text = tip
	if c is Label:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
