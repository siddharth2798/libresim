class_name OptionRows
extends RefCounted
## Row builders shared by the Options page tabs and the ATC options block. The one place that decides how
## an on / off option and a small choice look: a switch (SwitchRow) and a row of toggle buttons
## (Segmented). Every row reads its UserOptions key and writes it back at once (core/user_options.gd).

const LABEL_W := 170.0


## An on / off option as a switch (SwitchRow, with an optional description line under the title).
## `after(on)` runs after the value is stored (live apply, `changed`).
static func switch(text: String, key: String, after := Callable(), desc := "") -> SwitchRow:
	var sw := SwitchRow.new().setup(text, desc, bool(UserOptions.get_v(key)))
	sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sw.toggled.connect(func(on: bool):
		UserOptions.set_v(key, on)
		if after.is_valid():
			after.call(on))
	return sw


## A small choice (UserOptions.CHOICES[key]) as a label and a Segmented row of its values. `after(value)`
## runs after the value is stored.
static func choice(label: String, key: String, after := Callable(), tip := "") -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(LABEL_W, 0)
	l.add_theme_color_override("font_color", MenuTheme.DIM)
	if tip != "":
		SliderRow.tip_on(l, tip)
	hb.add_child(l)
	var seg := Segmented.new()
	seg.equal_width = false
	seg.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	seg.set_options(UserOptions.CHOICES[key], UserOptions.get_v(key))
	seg.selected.connect(func(v):
		UserOptions.set_v(key, v)
		if after.is_valid():
			after.call(v))
	hb.add_child(seg)
	return hb


## A tab body: a VBox with a section heading and (optionally) a note under it.
static func tab_body(title: String, note := "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(MenuTheme.heading(title))
	if note != "":
		v.add_child(MenuTheme.note(note))
	return v
