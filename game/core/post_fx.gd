class_name PostFx
extends RefCounted
## Post-processing entry point. Call apply() after the graphics preset is applied (Graphics.apply_to_scene) and whenever a
## post-fx option changes: PostFx.apply(root, Graphics.preset)
## It sets Environment glow from the "bloom" option (never on Low) and creates / reconfigures the "PostFxDriver" node under
## root (world/postfx/post_fx_driver.gd), which owns the effects:
##   motion_blur     CompositorEffect, compute (High+, Forward+)          world/postfx/motion_blur_effect.gd
##   sun_shafts      CompositorEffect, compute (Medium+, Forward+/Mobile) world/postfx/sun_shafts_effect.gd
##   sharpen, lens_effects, lens_rain   one canvas pass after TAA         world/postfx/screen_post.gd
##   heat_shimmer    full-screen quad on the camera (High+, Forward+)     world/postfx/heat_shimmer.gd
##   color_grading   Environment adjustments + generated LUT              world/postfx/color_grade.gd
##   depth_of_field  CameraAttributesPractical on the camera              (post_fx_driver.gd)
## Which effect runs is decided by PostFxRules.flags_for (options x preset x renderer), never by the effects.

const DRIVER := "PostFxDriver"


## The UserOptions values of every post-fx key (effect names + "bloom").
static func options() -> Dictionary:
	var out := {"bloom": UserOptions.get_v("bloom")}
	for fx in PostFxRules.FX:
		out[fx] = UserOptions.get_v(fx)
	return out


## Applies the post effects to a scene for a graphics preset; returns the flags used (for tests / the menu).
static func apply(root: Node, preset: String) -> Dictionary:
	if root == null:
		return {}
	var vp := root.get_viewport() if root.is_inside_tree() else null
	var flags := PostFxRules.flags_for(preset, RenderingServer.get_current_rendering_method(), options(),
		vp.use_taa if vp else false, vp.scaling_3d_scale if vp else 1.0)
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		we.environment.glow_enabled = flags.bloom
	var driver := root.get_node_or_null(DRIVER) as PostFxDriver
	if driver == null:
		driver = PostFxDriver.new()
		driver.name = DRIVER
		root.add_child(driver)
	driver.configure(root, flags)
	return flags
