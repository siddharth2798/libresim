extends GridContainer
## Read-only list of the hotkeys that are not rebindable (flight-control keys are
## edited in key_bindings_section.gd). Mirrors docs/USAGE.md. An entry with a third element
## (an action group) is listed only when the aircraft offers that group.

const KEYS := [
	["C / Shift+C, 1–8", "Camera views"],
	["Tab / Shift+Tab", "2D panel layout"],
	["V", "Re-centre view"],
	["N", "Moving map"],
	["T / P", "Taxi route / pushback"],
	["Backspace", "Dismiss the taxi message"],
	["`", "Radio (ATC) menu"],
	["F2", "Checklists"],
	["F9", "Failures panel"],
	["F10", "Settings"],
	["F11", "Saved flights"],
	["R", "Instant replay"],
	["H / F1 / F3", "HUD / key help / perf"],
	["J", "Controls panel"],
	["F5", "Reset to start"],
	["Esc", "Pause"],
	["L / Shift+L", "Panel lights brighter / dimmer"],
]

const WIDE_W := 560.0  # two pairs per row from this width

var controls: AircraftControls  # set before adding to the tree; default = the current aircraft
var _pairs: Array = []  # [key label, description label, text] per listed hotkey


func _ready() -> void:
	if controls == null:
		controls = AircraftControls.current()
	columns = 4
	resized.connect(func(): columns = 4 if size.x >= WIDE_W else 2)  # key | meaning pairs: two side by side, or one
	add_theme_constant_override("h_separation", 14)
	add_theme_constant_override("v_separation", 4)
	for k in KEYS:
		if k.size() > 2 and not controls.has_group(k[2]):
			continue
		var key := Label.new()
		key.text = k[0]
		key.add_theme_color_override("font_color", MenuTheme.ACCENT)
		key.add_theme_font_size_override("font_size", 14)
		add_child(key)
		var what := Label.new()
		what.text = k[1]
		what.add_theme_color_override("font_color", MenuTheme.DIM)
		what.add_theme_font_size_override("font_size", 14)
		what.size_flags_horizontal = SIZE_EXPAND_FILL
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a narrow window wraps the words instead of widening the page
		what.custom_minimum_size.x = 70.0
		add_child(what)
		_pairs.append([key, what, [k[0], k[1]]])


## Shows only the hotkeys that match the search words (controls_filter.gd); returns how many show.
func filter(query: String) -> int:
	var n := 0
	for p in _pairs:
		var ok := ControlsFilter.matches(query, p[2])
		p[0].visible = ok
		p[1].visible = ok
		n += int(ok)
	return n
