class_name ResolutionRow
extends HBoxContainer
## Options > Graphics: "Render resolution". Auto (the preset, and the Apple budget in core/render_budget.gd)
## or a fixed size from core/render_resolution.gd, listed for the screen the window is on now. The
## list rebuilds when the preset changes or the window moves to another screen.

signal changed

var _pick: OptionButton
var _opts := []  # RenderResolution.options() for the current frame; item i + 1


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = "Render resolution"
	l.custom_minimum_size = Vector2(OptionRows.LABEL_W, 0)
	l.add_theme_color_override("font_color", MenuTheme.DIM)
	var tip := "The size the 3D world is drawn at. Menus and the HUD stay sharp at the screen's own size. " \
		+ "Lower is faster and softer. Saved as a share of the screen, so it carries over to another display."
	SliderRow.tip_on(l, tip)
	add_child(l)
	_pick = OptionButton.new()
	_pick.custom_minimum_size = Vector2(260, 36)
	_pick.item_selected.connect(_on_pick)
	SliderRow.tip_on(_pick, tip)
	add_child(_pick)
	Graphics.changed.connect(_on_graphics)
	Graphics.screen_changed.connect(_on_graphics.bind(""))
	refresh()


func _on_graphics(_p: String) -> void:
	refresh.call_deferred()  # not while the OptionButton is still handling its own pick


## Rebuild the list for the current frame and select the saved choice (or the nearest size to it).
func refresh() -> void:
	var frame := Graphics.frame()
	_opts = RenderResolution.options(frame)
	_pick.clear()
	var auto := RenderBudget.clamp_preset(Graphics.PRESETS[Graphics.preset], frame, RenderBudget.apple_silicon())
	_pick.add_item("Auto: " + RenderResolution.label(frame, float(auto.scale)))
	for o in _opts:
		_pick.add_item(o.label)
	_pick.select(0 if Graphics.render_frac <= 0.0 else 1 + RenderResolution.nearest(_opts, Graphics.render_frac))


func _on_pick(i: int) -> void:
	Graphics.set_render_frac(0.0 if i == 0 else float(_opts[i - 1].frac))
	changed.emit()
