extends GridContainer
## Read-only keyboard reference (mirrors docs/USAGE.md "Flight controls (keyboard)").

const KEYS := [
	["↑ / ↓  (num 8 / 2)", "Pitch: ↓ pulls back, ↑ pushes"],
	["← / →  (num 4 / 6)", "Roll"],
	["Z / X  (num 0 / Enter)", "Rudder / nosewheel"],
	["PgUp / PgDn  (= / −)", "Throttle"],
	["' / ;", "Mixture richer / leaner"],
	["Home / End  (num 7 / 1)", "Trim nose down / up"],
	["] or F7 / [ or F6", "Flaps down / up"],
	["B (hold)", "Both brakes"],
	[", / . (hold)", "Left / right brake"],
	["Shift+B", "Parking brake"],
	["M", "Cycle magnetos"],
	["S (hold)", "Starter"],
	["Y", "Mouse yoke"],
	["C / Shift+C, 1–8", "Camera views"],
	["Tab / Shift+Tab", "2D panel layout"],
	["V", "Re-centre view"],
	["N", "Moving map"],
	["T / P", "Taxi route / pushback"],
	["`", "Radio (ATC) menu"],
	["F2", "Checklists"],
	["F9", "Failures panel"],
	["F10", "Settings"],
	["H / F1 / F3", "HUD / key help / perf"],
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
