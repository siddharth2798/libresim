class_name ScreenPost
extends CanvasLayer
## The final full-screen pass (screen_post.gdshader): sharpening, lens effects and lens rain. A CanvasLayer at
## layer -10: drawn after the 3D view (with Environment background "Sky" all canvas layers draw after 3D) and
## before every UI layer (they use 1 and up), so the HUD and menus are never sharpened or rained on.
## Hidden when nothing is on, so the screen copy is only paid when an effect is visible.

const LAYER := -10
## Defaults to tune by eye.
const SHARPEN := 0.35  # mild CAS
const VIGNETTE := 0.22
const ABERRATION := 0.006
const GRAIN := 0.025

var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()


func _init() -> void:
	name = "ScreenPost"
	layer = LAYER
	_mat.shader = preload("res://world/postfx/screen_post.gdshader")
	_rect.material = _mat
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	visible = false


## sharpen / lens: on or off; rain 0..1 with the airspeed (m/s) for the streaks.
func configure(sharpen: bool, lens: bool, rain: float, speed: float) -> void:
	_mat.set_shader_parameter("sharpen", SHARPEN if sharpen else 0.0)
	_mat.set_shader_parameter("vignette", VIGNETTE if lens else 0.0)
	_mat.set_shader_parameter("aberration", ABERRATION if lens else 0.0)
	_mat.set_shader_parameter("grain", GRAIN if lens else 0.0)
	_mat.set_shader_parameter("rain", rain)
	_mat.set_shader_parameter("rain_speed", speed)
	visible = sharpen or lens or rain > 0.001


func get_param(p: String) -> Variant:
	return _mat.get_shader_parameter(p)
