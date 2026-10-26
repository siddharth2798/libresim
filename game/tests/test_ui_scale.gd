extends Node
## UI scaling (core/ui_scale.gd): the factor chosen for a window size, and what a canvas_items
## window with that factor exposes to the UI code (the visible rect in UI units, expanding
## on the long side, never letterboxed).


func test_auto_factor_follows_the_limiting_side() -> String:
	var cases := {
		Vector2(1280, 720): 1.0, Vector2(1920, 1080): 1.5, Vector2(2560, 1440): 2.0, Vector2(3840, 2160): 3.0,
		Vector2(3440, 1440): 2.0, Vector2(5120, 1440): 2.0,  # ultrawide and 32:9: height limits
		Vector2(1280, 1600): 1.0, Vector2(640, 360): UiScale.MIN_AUTO,  # tiny windows keep readable text
	}
	for sz in cases:
		var f := UiScale.factor_for(sz, "Auto")
		if not is_equal_approx(f, cases[sz]):
			return "Auto at %s gave %.3f, expected %.3f" % [sz, f, cases[sz]]
	return ""


func test_fixed_percentages_follow_the_system_scale() -> String:
	if not is_equal_approx(UiScale.factor_for(Vector2(3840, 2160), "150%"), 1.5):
		return "150% should be 1.5 whatever the window size"
	if not is_equal_approx(UiScale.factor_for(Vector2(2560, 1440), "100%", 2.0), 2.0):
		return "100% on a 2x (Retina) screen should be 2.0"
	if not is_equal_approx(UiScale.factor_for(Vector2(1920, 1080), "garbage"), 1.5):
		return "an unknown choice should fall back to Auto"
	return ""


func test_every_choice_is_valid_and_auto_is_the_default() -> String:
	if UserOptions.DEFAULTS.ui_scale != "Auto":
		return "default UI size should be Auto"
	if UserOptions.CHOICES.ui_scale != UiScale.CHOICES:
		return "options choices and UiScale.CHOICES differ"
	for c in UiScale.CHOICES:
		if c != "Auto" and UiScale.factor_for(Vector2(1280, 720), c) <= 0.0:
			return "choice %s gives no factor" % c
	return ""


func test_scaled_window_exposes_ui_units_and_keeps_the_aspect() -> String:
	var err := ""
	for sz in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160), Vector2i(3440, 1440), Vector2i(5120, 1440), Vector2i(960, 540)]:
		var w := Window.new()
		w.size = sz
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		w.content_scale_factor = UiScale.factor_for(Vector2(sz), "Auto")
		w.visible = false
		add_child(w)
		var vr := w.get_visible_rect().size
		var f := w.content_scale_factor
		w.free()
		if absf(vr.x * f - sz.x) > 1.0 or absf(vr.y * f - sz.y) > 1.0:
			err = "window %s at factor %.2f exposes %s UI units (aspect not preserved)" % [sz, f, vr]
			break
		if vr.y < UiScale.DESIGN.y - 1.0 or vr.x < UiScale.DESIGN.x - 1.0:
			err = "window %s exposes only %s UI units, less than the %s design size" % [sz, vr, UiScale.DESIGN]
			break
	return err
