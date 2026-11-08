class_name RenderResolution
extends RefCounted
## The "Render resolution" choice: the size the 3D world is drawn at, shown as familiar resolutions
## (1920x1080) in the screen's own shape. The window and the UI always stay at the screen's native
## size; only the 3D scene is drawn smaller and upscaled (FSR2 on Forward+). The choice is saved as a
## fraction of the frame height, so it means the same on another screen (0 = Auto: the preset and
## core/render_budget.gd decide).

const HEIGHTS := [720, 900, 1080, 1440, 1800, 2160, 2880]
const MIN_FRAC := 0.25


## Choices for a `frame` (pixels): [{label, frac}], largest first, native at the top. Only sizes below the
## frame; heights closer than 8 % to another are dropped.
static func options(frame: Vector2i) -> Array:
	var h := maxi(frame.y, 1)
	var out := [{"label": label(frame, 1.0), "frac": 1.0}]
	var last := float(h)
	for i in range(HEIGHTS.size() - 1, -1, -1):
		var hh := float(HEIGHTS[i])
		if hh > last * 0.92 or hh / float(h) < MIN_FRAC:
			continue
		out.append({"label": label(frame, hh / float(h)), "frac": hh / float(h)})
		last = hh
	return out


## "1920×1080 (50%)" for a frame and a fraction of it.
static func label(frame: Vector2i, frac: float) -> String:
	var s := size_at(frame, frac)
	return "%d×%d (%d%%)" % [s.x, s.y, roundi(frac * 100.0)]


static func size_at(frame: Vector2i, frac: float) -> Vector2i:
	return Vector2i(roundi(frame.x * frac), roundi(frame.y * frac))


## Index in `opts` nearest to a saved fraction (a choice made on another screen lands on the closest size).
static func nearest(opts: Array, frac: float) -> int:
	var best := 0
	for i in opts.size():
		if absf(float(opts[i].frac) - frac) < absf(float(opts[best].frac) - frac):
			best = i
	return best


## The preset spec with the player's choice applied. `frac` 0 keeps the spec (Auto). A fixed choice
## replaces the scale, upscales with FSR (Forward+) below 1 and keeps FXAA when there is no MSAA.
static func apply(spec: Dictionary, frac: float) -> Dictionary:
	if frac <= 0.0:
		return spec
	var s := spec.duplicate()
	s.scale = clampf(frac, MIN_FRAC, 1.0)
	s.fsr = s.scale < 1.0
	if int(s.msaa) == 0:
		s.fxaa = true
	return s
