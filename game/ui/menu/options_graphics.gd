class_name OptionsGraphics
extends VBoxContainer
## The Graphics tab of the Options page: quality preset (Graphics autoload, same as F10), the renderer for
## the next start, and the post effect switches (ui/post_fx_toggles.gd). Presets Low / Medium run on the
## Mobile renderer, High and up on Forward+ (core/graphics_settings.gd); a preset on the other renderer
## shows "Restart libresim to apply".

signal changed

const PRESET_NOTES := {
	"low": "Mobile renderer. 70 % render scale with FSR, no shadows, short scenery range. For integrated graphics.",
	"medium": "Mobile renderer. 85 % render scale with FSR, shadows to 700 m, medium scenery range.",
	"high": "Forward+ renderer: ambient occlusion, more apron lights. Full resolution, MSAA 2x, shadows to 1.8 km, long scenery range.",
	"ultra": "Forward+: ambient occlusion, screen-space reflections on water and wet runways, TAA. MSAA 4x, shadows to 4 km, denser trees and buildings, more cloud steps.",
	"max": "Everything in Ultra plus indirect light (SSIL), 125 % supersampling, shadows to 6 km, 16 km buildings, the finest clouds. For a strong dedicated GPU.",
}
const RESTART_NOTE := "Restart libresim to apply: the next start uses the %s renderer."
const RENDERERS := {"Mobile": "mobile", "Forward+": "forward_plus"}

var restart_note: Label
var _preset_note: Label
var _presets := {}  # preset -> Button
var _renderer: PresetRow


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(MenuTheme.heading("Graphics quality"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var g := ButtonGroup.new()
	for p in Graphics.ORDER:
		var bt := Button.new()
		bt.text = p.capitalize()
		bt.toggle_mode = true
		bt.button_group = g
		bt.custom_minimum_size = Vector2(0, 40)
		bt.size_flags_horizontal = SIZE_EXPAND_FILL
		bt.button_pressed = p == Graphics.preset
		bt.pressed.connect(func():
			Graphics.set_preset(p)
			_preset_note.text = PRESET_NOTES.get(p, "")
			_refresh_restart()
			changed.emit())
		row.add_child(bt)
		_presets[p] = bt
	_preset_note = MenuTheme.note(PRESET_NOTES.get(Graphics.preset, ""))
	add_child(_preset_note)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 14)
	add_child(rr)
	var rl := Label.new()
	rl.text = "Renderer, next start"
	rl.custom_minimum_size = Vector2(OptionRows.LABEL_W, 0)
	rl.add_theme_color_override("font_color", MenuTheme.DIM)
	rr.add_child(rl)
	_renderer = PresetRow.new().setup(RENDERERS.keys(), RENDERERS.size())
	_renderer.picked.connect(func(k: String):
		Graphics.set_renderer(RENDERERS[k])
		_refresh_restart()
		changed.emit())
	rr.add_child(_renderer)
	restart_note = MenuTheme.note("")
	restart_note.add_theme_color_override("font_color", MenuTheme.WARN)
	add_child(restart_note)
	_refresh_restart()
	add_child(MenuTheme.heading("Post effects"))
	var fx := PostFxToggles.new()
	fx.cols = 2
	fx.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(fx)
	add_child(MenuTheme.note("Turn effects off on a weaker machine. Dimmed ones do not run on this preset (hover for why)."))


## "Restart to apply" while the renderer saved for the next start is not the running one; the renderer
## switches show the renderer the next start will use.
func _refresh_restart() -> void:
	var need := Graphics.restart_needed()
	var fp := Graphics.next_renderer() == "forward_plus"
	restart_note.text = RESTART_NOTE % ("Forward+" if fp else "Mobile") if need else ""
	restart_note.visible = need
	_renderer.select("Forward+" if fp else "Mobile")
