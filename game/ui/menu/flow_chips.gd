class_name FlowChips
extends Container
## The setup as clickable chips in the Free-flight footer: one small flat pill per key setting
## (aircraft, airport / start, weather, failures, recording), each with a status mark, and each
## jumps to its step (signal chip_pressed). The chips always stay on ONE row (the footer never grows
## taller): each takes its natural width while they all fit, otherwise the widest are shortened first and
## their text ends in an ellipsis (the tooltip has the whole text). Layout in fit_widths() (pure).
## Texts and levels come from FlowValues; the chips hold no state of their own.

signal chip_pressed(index: int)

const GAP := 5.0
const MIN_W := 72.0  # narrowest a chip is squeezed to: the mark and a few letters
const FONT_SIZE := 13
const PAD_LEFT := 24.0  # room for the status mark
const PAD_RIGHT := 8.0

var chips: Array[Button] = []
var _dots: Array[StatusDot] = []
var _natural: Array[float] = []  # width each chip would like (its text plus padding)


func _init() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_SHRINK_CENTER
	for i in FlowValues.KEYS.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_ALL
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_theme_font_size_override("font_size", FONT_SIZE)
		b.pressed.connect(func(): chip_pressed.emit(i))
		for k in ["normal", "hover", "pressed", "hover_pressed"]:
			var fill := Color(1, 1, 1, 0.07)
			if k == "hover":
				fill = MenuTheme.HOVER_FILL
			elif k != "normal":
				fill = Color(MenuTheme.ACCENT, 0.3)
			var sb := MenuTheme.box(fill, 16, MenuTheme.LINE, PAD_RIGHT)
			sb.content_margin_left = PAD_LEFT
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
		_natural.append(MIN_W)


## Repaint from the setup: `list` is SetupChecks.checks(setup).
func refresh(setup: Dictionary, list: Array) -> void:
	for i in chips.size():
		var key: String = FlowValues.KEYS[i]
		chips[i].text = FlowValues.chip_text(key, setup)
		_dots[i].level = FlowValues.level(key, setup, list)
		chips[i].tooltip_text = FlowValues.tooltip(key, setup, list, i)
		var font := chips[i].get_theme_font("font")
		_natural[i] = ceilf(font.get_string_size(chips[i].text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x) + PAD_LEFT + PAD_RIGHT + 2.0
	queue_sort()


func _get_minimum_size() -> Vector2:
	var h := 0.0
	for c in chips:
		h = maxf(h, c.get_combined_minimum_size().y)
	return Vector2(MIN_W * chips.size() + GAP * maxi(chips.size() - 1, 0), h)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		layout()


## Place the chips in one row, left to right, vertically centred.
func layout() -> void:
	var ws := fit_widths(_natural, size.x, GAP, MIN_W)
	var x := 0.0
	for i in chips.size():
		var h := chips[i].get_combined_minimum_size().y
		fit_child_in_rect(chips[i], Rect2(x, (size.y - h) / 2.0, ws[i], h))
		x += ws[i] + GAP


## Chip widths for a row `avail` wide: the natural widths when they fit with the gaps, else the widest chips are
## cut to one common width (never below `min_w`; a chip already narrower keeps its width).
static func fit_widths(natural: Array, avail: float, gap: float, min_w: float) -> Array:
	var room := avail - gap * maxi(natural.size() - 1, 0)
	var total := 0.0
	var widest := 0.0
	for w in natural:
		total += w
		widest = maxf(widest, w)
	if total <= room:
		return natural.duplicate()
	var lo := min_w
	var hi := widest
	for _i in 30:
		var mid := (lo + hi) / 2.0
		var sum := 0.0
		for w in natural:
			sum += minf(w, mid)
		if sum > room:
			hi = mid
		else:
			lo = mid
	return natural.map(func(w): return minf(w, lo))
