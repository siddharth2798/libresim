class_name RenderBudget
extends RefCounted
## The window framebuffer the 3D world is drawn into (what "native" means in the Render resolution list and for the
## auto scale). How big the 3D image is drawn is RenderScaler's job (measured GPU time, the same on every machine).

## Window framebuffer in pixels: the viewport texture when it exists (that is what is drawn), else the window
## size, which on macOS a small window reports in points (pick_frame).
static func frame_pixels(vp: Viewport) -> Vector2i:
	var tex := Vector2i.ZERO
	if vp:
		var t := vp.get_texture()
		if t:
			tex = t.get_size()
	return pick_frame(DisplayServer.window_get_size(), DisplayServer.screen_get_scale(), tex)


## The frame to budget for. tex: the viewport texture size (ZERO when there is none yet); win / scale: the
## window size and the screen scale. Before, a 1600x900 pixel window on a Retina screen was doubled to
## 3200x1800 and every preset was clamped to FSR2 at 0.7.
static func pick_frame(win: Vector2i, scale: float, tex: Vector2i) -> Vector2i:
	if tex.x > 16 and tex.y > 16:
		return tex
	if scale > 1.25 and win.x > 0 and win.x < 1800:
		win = Vector2i(Vector2(win) * scale)
	return win if win.x > 16 else Vector2i(1280, 720)
