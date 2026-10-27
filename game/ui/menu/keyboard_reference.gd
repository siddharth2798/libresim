extends GridContainer
## Read-only list of the hotkeys that are not rebindable (flight-control keys are
## edited in key_bindings_section.gd). Mirrors docs/USAGE.md.

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
]


func _ready() -> void:
	columns = 4
	add_theme_constant_override("h_separation", 14)
	add_theme_constant_override("v_separation", 4)
	for k in KEYS:
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
		add_child(what)
