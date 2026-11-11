extends Node
## Autoload "Graphics": quality presets (low / medium / high / ultra / max), saved in user://graphics.cfg,
## overridable with --quality=<preset>. Applies to viewport, environment, sun, shadow atlas and the scenery streamers
## (call apply_to_scene once the scene is ready).
## Each preset names a renderer: Low / Medium use Mobile, High and up use Forward+. Changing the renderer needs a
## restart: set_renderer() writes override.cfg and restart_needed() tells the menus.
## Preset keys: scale (3D render scale, > 1 supersample, < 1 bilinear on Mobile / FSR2 on Forward+), msaa (index into
## [off, 2x, 4x]), shadow (sun shadow distance, m), pssm (directional_shadow_mode), atlas / soft / pos_soft (shadow
## atlas size, soft filter quality of sun and omni / spot lights), ssao / ssil / taa (Forward+ only), ssr (ray steps,
## 0 = off, Forward+ only), cloud_light (light samples per cloud step), real_lights (real SpotLights on the nearest
## apron floodlights, world/apron_lamps.gd; Mobile lights a mesh with 8 spots, so Mobile is held to 4),
## apron_shadows (how many of them cast shadows, Forward+ only), vfog (volumetric fog level 0..3, Forward+ only,
## world/vfog_rules.gd).
const PRESETS := {
	"low": {"renderer": "mobile", "scale": 0.7, "fsr": true, "msaa": 0, "fxaa": true, "shadow": 0.0, "pssm": 0,
		"atlas": 2048, "soft": 1, "pos_soft": 1, "glow": false, "lod_k": 1.2, "bld": 4000.0, "trees": 1200.0,
		"tree_density": 0.5, "tree_lod": 0.0, "clouds": 10, "cloud_light": 1, "wisps": 0, "rain": 1500,
		"ssao": false, "ssil": false, "ssr": 0, "taa": false, "ae": false, "real_lights": 2, "apron_shadows": 0, "vfog": 0},
	"medium": {"renderer": "mobile", "scale": 0.85, "fsr": true, "msaa": 1, "fxaa": true, "shadow": 700.0, "pssm": 1,
		"atlas": 4096, "soft": 2, "pos_soft": 2, "glow": true, "lod_k": 1.4, "bld": 6000.0, "trees": 1800.0,
		"tree_density": 0.8, "tree_lod": 90.0, "clouds": 16, "cloud_light": 1, "wisps": 40, "rain": 3000,
		"ssao": false, "ssil": false, "ssr": 0, "taa": false, "ae": true, "real_lights": 4, "apron_shadows": 0, "vfog": 0},
	"high": {"renderer": "forward_plus", "scale": 1.0, "fsr": false, "msaa": 1, "fxaa": false, "shadow": 1800.0, "pssm": 2,
		"atlas": 4096, "soft": 3, "pos_soft": 2, "glow": true, "lod_k": 1.6, "bld": 9000.0, "trees": 2200.0,
		"tree_density": 1.0, "tree_lod": 120.0, "clouds": 24, "cloud_light": 2, "wisps": 80, "rain": 5000,
		"ssao": true, "ssil": false, "ssr": 0, "taa": false, "ae": true, "real_lights": 10, "apron_shadows": 0, "vfog": 1},
	"ultra": {"renderer": "forward_plus", "scale": 1.0, "fsr": false, "msaa": 2, "fxaa": false, "shadow": 4000.0, "pssm": 2,
		"atlas": 8192, "soft": 4, "pos_soft": 3, "glow": true, "lod_k": 2.0, "bld": 12000.0, "trees": 3000.0,
		"tree_density": 1.2, "tree_lod": 150.0, "clouds": 40, "cloud_light": 3, "wisps": 120, "rain": 8000,
		"ssao": true, "ssil": false, "ssr": 48, "taa": true, "ae": true, "real_lights": 16, "apron_shadows": 1, "vfog": 2},
	"max": {"renderer": "forward_plus", "scale": 1.25, "fsr": false, "msaa": 2, "fxaa": false, "shadow": 6000.0, "pssm": 2,
		"atlas": 8192, "soft": 5, "pos_soft": 4, "glow": true, "lod_k": 2.4, "bld": 16000.0, "trees": 4000.0,
		"tree_density": 1.4, "tree_lod": 250.0, "clouds": 64, "cloud_light": 4, "wisps": 160, "rain": 10000,
		"ssao": true, "ssil": true, "ssr": 64, "taa": true, "ae": true, "real_lights": 24, "apron_shadows": 2, "cloud_dist": 60000.0, "vfog": 3},
}
const ORDER := ["low", "medium", "high", "ultra", "max"]
const CFG := "user://graphics.cfg"
const OVERRIDE := "override.cfg"

var preset := "high"
## Render resolution as a fraction of the frame height (core/render_resolution.gd); 0 = Auto.
var render_frac := 0.0
var _watch := {}  # screen, window size and 3D scale at the last apply (screen changes re-apply)
var _watch_t := 0.0
## Renderer saved to override.cfg for the next start ("" = none saved in this run).
var _pending_renderer := ""
## --quality=<preset> is a one-off for this run: it never saves a renderer (pass --rendering-method for one).
var _quality_cli := false
## Tests only: the folder of override.cfg ("" = next to the project / the executable) and a pretend running renderer.
var override_dir := ""
var running_override := ""
var _atlas := [-1, -1, -1]  # last atlas size / soft qualities sent to the RenderingServer
signal changed(preset: String)
## The renderer saved for the next start differs from the running one (or matches it again).
signal restart_needed_changed(needed: bool)
## The window moved to another screen or changed size (the resolution list should rebuild).
signal screen_changed


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		preset = cf.get_value("graphics", "preset", preset)
		render_frac = float(cf.get_value("graphics", "render_frac", 0.0))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			preset = a.substr(10).to_lower()
			_quality_cli = true
	if not PRESETS.has(preset):
		preset = "high"
	_match_renderer_once.call_deferred()  # deferred: Session (autoloaded after us) decides interactive()


## The renderer actually running ("forward_plus", "mobile" or "gl_compatibility"); also right when it
## was picked with --rendering-method or override.cfg rather than project.godot.
func renderer() -> String:
	return running_override if running_override != "" else RenderingServer.get_current_rendering_method()


## The renderer a preset is meant to run on.
func preset_renderer(p: String) -> String:
	return PRESETS.get(p, PRESETS.high).renderer


## True when a different renderer has been saved and only takes effect after a restart.
func restart_needed() -> bool:
	return _pending_renderer != "" and _pending_renderer != renderer()


## The renderer the next start will use: the saved choice while a restart is pending, else the running one.
func next_renderer() -> String:
	return _pending_renderer if restart_needed() else renderer()


## Advice for the menus when preset `p` is designed for a renderer other than `next` (a manual renderer choice
## stands, so this only tells); "" when they agree. Low / Medium on Forward+ is the case that shimmers at thin
## edges (docs/FLICKER-PLAN.md).
static func renderer_note(p: String, next: String) -> String:
	var want: String = PRESETS.get(p, PRESETS.high).renderer
	if want == next or not next in ["mobile", "forward_plus"]:  # headless / compatibility runs: nothing to advise
		return ""
	var name := {"mobile": "Mobile", "forward_plus": "Forward+"}
	return "%s is designed for the %s renderer; %s was chosen by hand." % [p.capitalize(), name.get(want, want), name.get(next, next)]


func set_preset(p: String) -> void:
	if not PRESETS.has(p):
		return
	preset = p
	if Session.interactive():
		_save()
		var want := preset_renderer(p)
		# Also rewrite when going back to the running renderer, so a pending switch is cancelled.
		if want != renderer() or _pending_renderer != "":
			set_renderer(want)
	apply_to_scene(get_tree().current_scene)
	changed.emit(p)


## Render resolution: a fraction of the frame height (RenderResolution), 0 = Auto. Applies at once.
func set_render_frac(f: float) -> void:
	render_frac = maxf(f, 0.0)
	if Session.interactive():
		_save()
	apply_to_scene(get_tree().current_scene)
	changed.emit(preset)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("graphics", "preset", preset)
	cf.set_value("graphics", "render_frac", render_frac)
	cf.save(CFG)


## The window framebuffer in pixels (what "native" means in the resolution list).
func frame() -> Vector2i:
	return RenderBudget.frame_pixels(get_tree().root)


## The preset as it runs here: the Apple budget (Auto), then the player's resolution choice.
## Headless runs (tests) keep the preset numbers.
func spec_for(pixels: Vector2i) -> Dictionary:
	var s: Dictionary = PRESETS[preset]
	if DisplayServer.get_name() == "headless":
		return s
	s = RenderBudget.clamp_preset(s, pixels, RenderBudget.apple_silicon())
	return RenderResolution.apply(s, render_frac)


## A window moved to another screen, a display plugged in, or a resize: once it has settled, apply again so
## Auto and the resolution list fit the new frame. Checked once a second.
func _process(dt: float) -> void:
	_watch_t += dt
	if _watch_t < 1.0 or DisplayServer.get_name() == "headless":
		return
	_watch_t = 0.0
	var now := _watch_key()
	if not _watch.is_empty() and now != _watch and get_tree().current_scene:
		apply_to_scene(get_tree().current_scene)
		screen_changed.emit()
	_watch = now


func _watch_key() -> Dictionary:
	var sc := DisplayServer.window_get_current_screen()
	return {"screen": sc, "size": DisplayServer.screen_get_size(sc), "win": DisplayServer.window_get_size()}


## Persist a renderer choice ("mobile" or "forward_plus"); takes effect on restart. Also the manual
## F10 toggle: the choice stands until the next preset change on the other renderer.
func set_renderer(method: String) -> void:
	if _may_write():  # tests, probes and headless runs never leave an override.cfg behind
		var f := FileAccess.open(_override_path(), FileAccess.WRITE)
		if f:
			f.store_string("[rendering]\nrenderer/rendering_method=\"%s\"\n" % method)
	var was := restart_needed()
	_pending_renderer = method
	if restart_needed() != was:
		restart_needed_changed.emit(restart_needed())


## May this run save a renderer? Only a real player run: interactive (core/save_guard.gd) and not headless (a headless
## run has no restart prompt; a test that flips Session.interactive_override must not reach the real file). A test
## that sets `override_dir` to a scratch folder is exempt from the headless rule.
func _may_write() -> bool:
	return Session.interactive() and (override_dir != "" or DisplayServer.get_name() != "headless")


func _override_path() -> String:
	if override_dir != "":
		return override_dir.path_join(OVERRIDE)
	var dir := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	return dir.path_join(OVERRIDE)


## First start after the default became Forward+: if no renderer was ever chosen (no override.cfg), save the
## preset's own so a Low / Medium player on integrated GPU is not moved to Forward+; the menus then say "restart to apply".
## Not for a --quality= run (a one-off must not change the next start).
func _match_renderer_once() -> void:
	if _quality_cli or not _may_write() or FileAccess.file_exists(_override_path()):
		return
	if preset_renderer(preset) != renderer() and renderer() in ["mobile", "forward_plus"]:
		set_renderer(preset_renderer(preset))


func apply_to_scene(root: Node) -> void:
	if root == null:
		return
	var s := spec_for(RenderBudget.frame_pixels(root.get_viewport()))
	if DisplayServer.get_name() != "headless":
		_watch = _watch_key()
	var forward_plus := renderer() == "forward_plus"
	_apply_shadow_atlas(s)
	var vp := root.get_viewport()
	_apply_viewport(vp, s, forward_plus)
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = s.shadow > 0.0
		sun.directional_shadow_max_distance = maxf(s.shadow, 10.0)
		sun.directional_shadow_mode = s.pssm  # 0 one orthogonal split, 1 two splits, 2 four (cascades)
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		_apply_environment(we.environment, s, forward_plus)
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
		tr.lod_radius = s.tree_lod  # real tree meshes within this radius (0 = none)
	var rl := root.get_node_or_null("RunwayLights")
	if rl and rl.has_method("set_real_lights"):
		rl.set_real_lights(s.real_lights if forward_plus else mini(s.real_lights, 4), s.apron_shadows if forward_plus else 0)
	var fx := root.get_node_or_null("SkyTime/WeatherFx")
	if fx:
		fx.set_rain_max(s.rain)  # rain streaks at full rain
	var sky_time := root.get_node_or_null("SkyTime") as SkyTime
	if sky_time:
		sky_time.auto_exposure = s.ae  # eye-like auto exposure (world/auto_exposure.gd), off on Low
	var cam := vp.get_camera_3d()
	var cl := cam.get_node_or_null("CloudLayer") if cam else null
	if cl:
		cl.steps = s.clouds
		if "light_steps" in cl:  # light samples per raymarch step (world/cloud_layer.gd)
			cl.light_steps = s.cloud_light
		if "max_dist" in cl: cl.max_dist = s.get("cloud_dist", 25000.0)  # cloud march range (m), longer on Max; fades out before it (G4)
	if cam and cam.get_node_or_null("CloudWisps"):
		cam.get_node("CloudWisps").set_count(s.wisps)  # in-cloud wisps (motion cue), none on Low
	if cam and cam.get_node_or_null("SunGlare"):
		cam.get_node("SunGlare").enabled = preset != "low"
	VolumetricFog.apply(root, s.vfog)  # near-field froxel fog (world/volumetric_fog.gd), Forward+ / High+ only
	PostFx.apply(root, preset)  # bloom, motion blur and the other post effects (user options x this preset)


## Supersampling above 1 is a plain bilinear downscale. Below 1, Forward+ uses FSR2, which
## antialiases itself, so TAA is off. The mobile renderer has no FSR, so it stays bilinear.
func _apply_viewport(vp: Viewport, s: Dictionary, forward_plus: bool) -> void:
	var up: bool = s.fsr and s.scale < 1.0 and forward_plus
	if up:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s.scale
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][s.msaa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if s.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_debanding = true  # dither before the 8-bit output: smooth dark sky gradients and fog do not band
	vp.use_taa = s.taa and forward_plus and not (up and forward_plus)


## SSAO / SSIL / SSR exist only on Forward+; they are switched off elsewhere so saved scenes behave the same.
func _apply_environment(env: Environment, s: Dictionary, forward_plus: bool) -> void:
	env.glow_enabled = s.glow
	env.ssao_enabled = s.ssao and forward_plus
	env.ssil_enabled = s.ssil and forward_plus
	env.ssr_enabled = s.ssr > 0 and forward_plus
	# water (terrain_water.gdshaderinc) tones down its fake sky reflection when SSR draws the real one
	RenderingServer.global_shader_parameter_set("water_ssr", 1.0 if env.ssr_enabled else 0.0)
	if env.ssr_enabled:
		env.ssr_max_steps = s.ssr
		env.ssr_fade_in = 0.15   # Godot's defaults: soft edge where the ray starts and where it ends
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.5


## The shadow atlas and soft-shadow filters are global (RenderingServer), not per viewport; only
## sent when they change, since a new atlas size reallocates it.
func _apply_shadow_atlas(s: Dictionary) -> void:
	var want := [int(s.atlas), int(s.soft), int(s.pos_soft)]
	if want == _atlas:
		return
	_atlas = want
	RenderingServer.directional_shadow_atlas_set_size(want[0], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(want[1] as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(want[2] as RenderingServer.ShadowQuality)
