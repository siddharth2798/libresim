extends Node
## Autoload "Graphics": quality presets (low / medium / high / ultra), saved in
## user://graphics.cfg, overridable with --quality=<preset> on the command line.
## Applies to the viewport, environment, sun and the scenery streamers of the
## current scene (call apply_to_scene after the scene is ready).
## The renderer itself (Mobile vs Forward+) needs a restart: set_renderer() writes
## override.cfg next to the project / executable.

const PRESETS := {
	"low": {"scale": 0.7, "fsr": true, "msaa": 0, "fxaa": true, "shadow": 0.0, "pssm": 0, "glow": false,
		"lod_k": 1.2, "bld": 4000.0, "trees": 1200.0, "tree_density": 0.5, "clouds": 10, "rain": 1500, "ssao": false, "taa": false},
	"medium": {"scale": 0.85, "fsr": true, "msaa": 1, "fxaa": true, "shadow": 700.0, "pssm": 1, "glow": true,
		"lod_k": 1.4, "bld": 6000.0, "trees": 1800.0, "tree_density": 0.8, "clouds": 16, "rain": 3000, "ssao": false, "taa": false},
	"high": {"scale": 1.0, "fsr": false, "msaa": 1, "fxaa": false, "shadow": 1800.0, "pssm": 2, "glow": true,
		"lod_k": 1.6, "bld": 9000.0, "trees": 2200.0, "tree_density": 1.0, "clouds": 24, "rain": 5000, "ssao": false, "taa": false},
	"ultra": {"scale": 1.0, "fsr": false, "msaa": 2, "fxaa": false, "shadow": 4000.0, "pssm": 2, "glow": true,
		"lod_k": 2.0, "bld": 12000.0, "trees": 3000.0, "tree_density": 1.2, "clouds": 40, "rain": 8000, "ssao": true, "taa": true},
}
const ORDER := ["low", "medium", "high", "ultra"]
const CFG := "user://graphics.cfg"

var preset := "high"
signal changed(preset: String)


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		preset = cf.get_value("graphics", "preset", preset)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			preset = a.substr(10).to_lower()
	if not PRESETS.has(preset):
		preset = "high"


func renderer() -> String:
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "mobile"))


func set_preset(p: String) -> void:
	if not PRESETS.has(p):
		return
	preset = p
	var cf := ConfigFile.new()
	cf.set_value("graphics", "preset", p)
	cf.save(CFG)
	apply_to_scene(get_tree().current_scene)
	changed.emit(p)


## Persist a renderer choice ("mobile" or "forward_plus"); takes effect on restart.
func set_renderer(method: String) -> void:
	var dir := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	var f := FileAccess.open(dir.path_join("override.cfg"), FileAccess.WRITE)
	if f:
		f.store_string("[rendering]\nrenderer/rendering_method=\"%s\"\n" % method)


func apply_to_scene(root: Node) -> void:
	if root == null:
		return
	var s: Dictionary = PRESETS[preset]
	var vp := root.get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s.fsr else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s.scale
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][s.msaa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if s.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	var forward_plus := renderer() == "forward_plus"
	vp.use_taa = s.taa and forward_plus
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = s.shadow > 0.0
		sun.directional_shadow_max_distance = maxf(s.shadow, 10.0)
		sun.directional_shadow_mode = s.pssm  # 0 one orthogonal split, 1 two splits, 2 four (cascades)
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		we.environment.glow_enabled = s.glow
		we.environment.ssao_enabled = s.ssao and forward_plus
	var t := root.get_node_or_null("Terrain")
	if t:
		t.lod_k = s.lod_k
	var b := root.get_node_or_null("Buildings")
	if b:
		b.radius = s.bld
	var tr := root.get_node_or_null("Trees")
	if tr:
		tr.radius = s.trees
		tr.density_scale = s.tree_density
	var fx := root.get_node_or_null("SkyTime/WeatherFx")
	if fx:
		fx.set_rain_max(s.rain)  # rain streaks at full rain
	var cam := vp.get_camera_3d()
	if cam and cam.get_node_or_null("CloudLayer"):
		cam.get_node("CloudLayer").steps = s.clouds
	if cam and cam.get_node_or_null("SunGlare"):
		cam.get_node("SunGlare").enabled = preset != "low"
