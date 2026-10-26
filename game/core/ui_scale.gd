extends Node
## Autoload "UiScale": one place that scales all 2D UI (HUD, panels, menus, ATC, map) to the
## window. The project uses the canvas_items stretch mode, so only the canvas is scaled (text and
## shapes are redrawn crisp at the new size) and the 3D scene keeps the window's native
## resolution. All UI code keeps working in virtual units (about 1280x720 at 100 %); a wider or
## taller window just shows more of them (stretch aspect "expand", nothing letterboxed).
## Option "ui_scale" (Options > Display): Auto or a fixed percentage.

const DESIGN := Vector2(1280.0, 720.0)  # UI units that fill a window at factor 1
const MIN_AUTO := 0.75  # below this a small window shows more UI units instead of shrinking text
const MAX_FACTOR := 6.0
const CHOICES := ["Auto", "100%", "125%", "150%", "200%"]

var factor := 1.0
signal changed(factor: float)


func _ready() -> void:
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i.ZERO  # factor-driven, not a fixed base size
	w.size_changed.connect(apply)
	apply()


## Factor for a window of this size in pixels. choice: "Auto" fits the window to DESIGN by
## its limiting side; "125%" etc. mean that fraction of the operating system's UI scale
## (os_scale is 2 on a Retina screen, so 100 % there is the same size as an OS dialog).
static func factor_for(window_px: Vector2, choice: String, os_scale := 1.0) -> float:
	if choice.ends_with("%"):
		return clampf(float(choice.trim_suffix("%")) / 100.0 * maxf(os_scale, 0.5), 0.5, MAX_FACTOR)
	var k := minf(window_px.x / DESIGN.x, window_px.y / DESIGN.y)
	return clampf(k, MIN_AUTO, MAX_FACTOR)


## Re-read the option and the window size and apply the result (also after a window resize).
func apply() -> void:
	var w := get_window()
	if DisplayServer.get_name() == "headless" and w.size.x < 256:
		return  # headless root window is a 64 px stub; keep factor 1 so layouts stay testable
	var os_scale := DisplayServer.screen_get_scale(w.current_screen) if DisplayServer.get_name() != "headless" else 1.0
	var f := factor_for(Vector2(w.size), str(UserOptions.get_v("ui_scale")), os_scale)
	if not is_equal_approx(f, w.content_scale_factor):
		w.content_scale_factor = f
	if not is_equal_approx(f, factor):
		factor = f
		changed.emit(f)
