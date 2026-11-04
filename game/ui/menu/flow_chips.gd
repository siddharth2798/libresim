class_name FlowChips
extends HFlowContainer
## The setup as clickable chips in the Free-flight footer: one small flat pill per key setting
## (aircraft, airport / start, weather, failures, recording), each with a status mark, and each
## jumps to its step (signal chip_pressed). They wrap onto a second row instead of overflowing.
## Texts and levels come from FlowValues; the chips hold no state of their own.

signal chip_pressed(index: int)

var chips: Array[Button] = []
var _dots: Array[StatusDot] = []


func _init() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_SHRINK_CENTER
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 6)
	for i in FlowValues.KEYS.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_ALL
		b.clip_text = false
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): chip_pressed.emit(i))
		for k in ["normal", "hover", "pressed", "hover_pressed"]:
			var fill := Color(1, 1, 1, 0.07)
			if k == "hover":
				fill = MenuTheme.HOVER_FILL
			elif k != "normal":
				fill = Color(MenuTheme.ACCENT, 0.3)
			var sb := MenuTheme.box(fill, 16, MenuTheme.LINE, 10.0)
			sb.content_margin_left = 25.0  # room for the status mark
			sb.content_margin_top = 5.0
			sb.content_margin_bottom = 5.0
			b.add_theme_stylebox_override(k, sb)
		# no "focus" override: the theme's accent ring stays
		var dot := StatusDot.new("none", 11)
		dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
		dot.offset_left = 10
		dot.offset_right = 21
		dot.offset_top = -5.5
		dot.offset_bottom = 5.5
		b.add_child(dot)
		add_child(b)
		chips.append(b)
		_dots.append(dot)


## Repaint from the setup: `list` is SetupChecks.checks(setup).
func refresh(setup: Dictionary, list: Array) -> void:
	for i in chips.size():
		var key: String = FlowValues.KEYS[i]
		chips[i].text = FlowValues.chip_text(key, setup)
		_dots[i].level = FlowValues.level(key, setup, list)
		chips[i].tooltip_text = FlowValues.tooltip(key, setup, list, i)
