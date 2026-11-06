class_name RenderBudget
extends RefCounted
## A fanless Apple Silicon Mac shares one memory pool and has no spare pixels. The
## preset still names the look; this clamps the costs that scale with the framebuffer
## (the cloud march, MSAA, the shadow map) so a 16 GB Air stays near its refresh rate.
## Headless runs do not call this (tests keep the preset numbers).

const PIXEL_CAP := 1600000  # about 1600x1000 of 3D, before the UI


static func apple_silicon() -> bool:
	return OS.get_name() == "macOS" and "Apple" in OS.get_processor_name()


## Window framebuffer in pixels. On macOS a small window size is in points.
static func frame_pixels(vp: Viewport) -> Vector2i:
	var win := DisplayServer.window_get_size()
	var sc := DisplayServer.screen_get_scale()
	if sc > 1.25 and win.x > 0 and win.x < 1800:
		win = Vector2i(Vector2(win) * sc)
	if vp:
		var tex := vp.get_texture()
		if tex and tex.get_width() > win.x and tex.get_height() > 16:
			win = tex.get_size()
	return win if win.x > 16 else Vector2i(1280, 720)


## A copy of the preset. `pixels` is the window framebuffer. Other machines pass through.
static func clamp_preset(spec: Dictionary, pixels: Vector2i, apple: bool) -> Dictionary:
	var s := spec.duplicate()
	if not apple:
		return s
	var px := maxi(pixels.x, 1) * maxi(pixels.y, 1)
	if px > PIXEL_CAP:
		s.scale = minf(float(s.scale), sqrt(float(PIXEL_CAP) / float(px)))
	s.msaa = 0
	s.clouds = mini(int(s.clouds), 10)
	s.cloud_light = 1
	s.atlas = mini(int(s.atlas), 2048)
	if float(s.shadow) > 0.0:
		s.shadow = minf(float(s.shadow), 500.0)
	s.tree_lod = minf(float(s.tree_lod), 60.0)
	s.wisps = mini(int(s.wisps), 40)
	s.real_lights = mini(int(s.real_lights), 4)
	return s
