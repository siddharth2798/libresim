class_name PostFxToggles
extends GridContainer
## On / off switches for bloom and the post effects (core/post_fx.gd), shared by the start-screen
## Options page and the in-flight settings (F10 / pause). Each switch writes its UserOptions key and
## re-applies the effects to the running scene at once. A switch whose effect cannot run on the current
## preset / renderer stays clickable (the choice is kept for later) but is dimmed, with the reason as
## its tooltip, so weaker machines can see what they are not getting and why.

const ROWS := [
	# [UserOptions key, label]
	["bloom", "Bloom (glow around bright lights)"],
	["motion_blur", "Motion blur"],
	["sun_shafts", "Sun shafts"],
	["sharpen", "Sharpening (after TAA / scaling)"],
	["color_grading", "Colour grading (time of day, weather)"],
	["heat_shimmer", "Heat shimmer (hot ground, exhausts)"],
	["lens_rain", "Rain on the lens (outside views)"],
	["lens_effects", "Lens effects (vignette, fringing, grain)"],
	["depth_of_field", "Depth of field (replay / free camera)"],
	["volumetric_fog", "Volumetric fog (light shafts, rain curtains, mist)"],
]

var _boxes := {}


func _ready() -> void:
	columns = 1
	for r in ROWS:
		var cb := CheckBox.new()
		cb.text = r[1]
		cb.button_pressed = bool(UserOptions.get_v(r[0]))
		cb.toggled.connect(func(on: bool):
			UserOptions.set_v(r[0], on)
			var scene := get_tree().current_scene
			if scene:
				PostFx.apply(scene, Graphics.preset)
			refresh())
		add_child(cb)
		_boxes[r[0]] = cb
	Graphics.changed.connect(func(_p): refresh())
	refresh()


## Dims the switches whose effect the current preset / renderer cannot run.
func refresh() -> void:
	var rend := Graphics.renderer()
	for key in _boxes:
		var cb: CheckBox = _boxes[key]
		var why := _why_not(key, Graphics.preset, rend)
		cb.modulate.a = 1.0 if why == "" else 0.55
		cb.tooltip_text = why


static func _why_not(key: String, preset: String, rend: String) -> String:
	if key == "bloom":
		return "Not on the Low preset." if preset == "low" else ""
	if not PostFxRules.FX.has(key):
		return ""
	var fx: Dictionary = PostFxRules.FX[key]
	if PostFxRules.rank(preset) < PostFxRules.rank(fx.min):
		return "Needs the %s preset or higher." % str(fx.min).capitalize()
	if not rend in fx.renderers:
		return "Needs the Forward+ renderer (High preset or higher, after a restart)."
	return ""
