class_name PresetRow
extends GridContainer
## A row of toggle buttons for presets (weather, time of day, wind). Exactly one can show
## the selected look (the theme's "pressed" style); select("") clears it, for values that
## no longer match any preset. Clicking only emits picked(); the page applies the preset
## and calls select() again, so the highlight always follows the real values.

signal picked(key: String)

var _btns := {}


func setup(keys: Array, cols: int) -> PresetRow:
	columns = cols
	for k in keys:
		var b := Button.new()
		b.text = str(k)
		b.toggle_mode = true
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(func(): picked.emit(str(k)))
		add_child(b)
		_btns[str(k)] = b
	return self


## Highlight `key` (and only it); "" or an unknown key highlights nothing.
func select(key: String) -> void:
	for k in _btns:
		(_btns[k] as Button).set_pressed_no_signal(k == key)


func selected() -> String:
	for k in _btns:
		if (_btns[k] as Button).button_pressed:
			return k
	return ""
