extends RefCounted
## Every export preset bakes its shaders (export_presets.cfg shader_baker/enabled, Godot 4.5+), so a fresh install does
## not compile them on the first start. The baker only runs for Forward+ / Mobile on a RenderingDevice driver, never for a
## dedicated server export; tools/package/make_release.sh exports with a GPU so it can bake (docs/USAGE.md "Packaging").

const PRESETS := "res://export_presets.cfg"


func _sections() -> Array:
	var cf := ConfigFile.new()
	if cf.load(PRESETS) != OK:
		return []
	var out := []
	for sec in cf.get_sections():
		if sec.begins_with("preset.") and not sec.ends_with(".options"):
			out.append([sec, cf])
	return out


func test_every_export_preset_bakes_shaders() -> String:
	var secs := _sections()
	if secs.is_empty():
		return "no export presets in " + PRESETS
	for s in secs:
		var sec: String = s[0]
		var cf: ConfigFile = s[1]
		var name := str(cf.get_value(sec, "name", sec))
		if not cf.has_section(sec + ".options"):
			return "%s has no options section" % name
		if cf.get_value(sec + ".options", "shader_baker/enabled", false) != true:
			return "%s: shader_baker/enabled is not true" % name
		if cf.get_value(sec, "dedicated_server", false):
			return "%s is a dedicated server export: the baker skips those" % name
	return ""


func test_desktop_platforms_have_presets() -> String:
	var platforms := []
	for s in _sections():
		platforms.append(str(s[1].get_value(s[0], "platform", "")))
	for want in ["Linux", "macOS"]:
		if not want in platforms:
			return "no %s export preset (have %s)" % [want, platforms]
	return ""


func test_project_renderer_can_be_baked() -> String:
	# The baker has nothing to do on the Compatibility renderer; the packages start on the project's Forward+.
	var cf := ConfigFile.new()
	if cf.load("res://project.godot") != OK:
		return "project.godot did not load"
	var method := str(cf.get_value("rendering", "renderer/rendering_method", "forward_plus"))
	return "" if method in ["forward_plus", "mobile"] else "rendering_method %s cannot be baked" % method


## The macOS build targets macOS 14 (chosen 2026-11-18): the Forward+ scene shader, volumetric fog and FSR2 need Metal Shading
## Language 3.1, so below 14 the baker leaves them to compile on the player's Mac.
func test_macos_minimum_lets_forward_plus_shaders_bake() -> String:
	for s in _sections():
		var sec: String = s[0]
		var cf: ConfigFile = s[1]
		if str(cf.get_value(sec, "platform", "")) != "macOS":
			continue
		for key in ["application/min_macos_version_arm64", "application/min_macos_version_x86_64"]:
			var v := float(str(cf.get_value(sec + ".options", key, "0")))
			if v < 14.0:
				return "%s is %s, below 14.0 (MSL 3.1)" % [key, v]
		return ""
	return "no macOS preset"
