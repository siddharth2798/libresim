class_name MapView
extends RefCounted
## Pure view maths of the moving map (no nodes, no drawing): world <-> screen, zoom around a
## point with an exponential ease, pan, fit-to-points, scale bar length, imagery level choice
## and segment clipping. World = ENU metres (x east, y north); screen = UI units (y down).
## `rot` turns the map on screen (0 = north up, -heading = heading up).

const NM := 1852.0
const MIN_ACROSS_NM := 0.3
const MAX_ACROSS_NM := 300.0
const DEFAULT_ACROSS_NM := 20.0
const EASE_RATE := 12.0  # 1/s: how fast the scale closes on its target
const TILE_PX := 768.0  # imagery tile size in pixels (tools/02_dem_tiles.py)
const LEVEL0_M_PER_PX := 10.0  # level-0 imagery resolution

var size := Vector2(1280.0, 720.0)
var centre := Vector2.ZERO
var m_per_px := 30.0
var target_m_per_px := 30.0
var rot := 0.0

var _anchor_px := Vector2.ZERO
var _anchor_world := Vector2.ZERO
var _anchor_on := false


func min_mpp() -> float:
	return MIN_ACROSS_NM * NM / maxf(size.x, 1.0)


func max_mpp() -> float:
	return MAX_ACROSS_NM * NM / maxf(size.x, 1.0)


func clamp_mpp(v: float) -> float:
	return clampf(v, min_mpp(), max_mpp())


func across_nm() -> float:
	return size.x * m_per_px / NM


## Width of the view in nautical miles, set at once (no ease).
func set_across_nm(nm: float) -> void:
	m_per_px = clamp_mpp(nm * NM / maxf(size.x, 1.0))
	target_m_per_px = m_per_px
	_anchor_on = false


func to_px(w: Vector2) -> Vector2:
	var d := (w - centre) / m_per_px
	return size * 0.5 + Vector2(d.x, -d.y).rotated(rot)


func to_world(p: Vector2) -> Vector2:
	var v := (p - size * 0.5).rotated(-rot)
	return centre + Vector2(v.x, -v.y) * m_per_px


## Metres per screen pixel scaled to physical pixels (ui = UiScale.factor), for the imagery choice.
func physical_m_per_px(ui: float) -> float:
	return m_per_px / maxf(ui, 0.1)


func pan_px(delta: Vector2) -> void:
	var v := delta.rotated(-rot)
	centre += Vector2(-v.x, v.y) * m_per_px


## Zoom by `factor` (< 1 zooms in) towards a scale clamped to the range; the world point under
## `px` stays under it while the scale eases.
func zoom_at(px: Vector2, factor: float) -> void:
	target_m_per_px = clamp_mpp(target_m_per_px * factor)
	_anchor_px = px
	_anchor_world = to_world(px)
	_anchor_on = true


## Advance the scale ease by dt seconds. Returns true while it is still moving.
func step(dt: float) -> bool:
	if is_equal_approx(m_per_px, target_m_per_px):
		m_per_px = target_m_per_px
		_anchor_on = false
		return false
	var k := 1.0 - exp(-EASE_RATE * dt)
	var next := exp(lerpf(log(m_per_px), log(target_m_per_px), k))
	if absf(next / target_m_per_px - 1.0) < 0.002:
		next = target_m_per_px
	m_per_px = next
	if _anchor_on:
		pan_px(_anchor_px - to_px(_anchor_world))
	return m_per_px != target_m_per_px


## World AABB of the visible area (all four corners, so a rotated view is covered).
func world_bounds() -> Rect2:
	var r := Rect2(to_world(Vector2.ZERO), Vector2.ZERO)
	for c in [Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		r = r.expand(to_world(c))
	return r


## Scale (m per px) at which every point is on screen with the view centred on `at`
## (the aircraft stays in the middle), never closer than `min_nm` across. pad_px keeps the
## points off the edge.
func scale_around(at: Vector2, pts: Array, pad_px: float, min_nm: float = DEFAULT_ACROSS_NM) -> float:
	var need := min_nm * NM / maxf(size.x, 1.0)
	var half := size * 0.5 - Vector2(pad_px, pad_px)
	half = Vector2(maxf(half.x, 40.0), maxf(half.y, 40.0))
	for p in pts:
		var d: Vector2 = p - at
		var v := Vector2(d.x, -d.y).rotated(rot)
		need = maxf(need, maxf(absf(v.x) / half.x, absf(v.y) / half.y))
	return clamp_mpp(need)


## Centre on the middle of the points' bounding box and scale so all of them fit (north-up).
func fit_bounds(pts: Array, pad_px: float) -> void:
	if pts.is_empty():
		return
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	centre = r.get_center()
	var half := Vector2(maxf(size.x * 0.5 - pad_px, 40.0), maxf(size.y * 0.5 - pad_px, 40.0))
	var need := maxf(r.size.x * 0.5 / half.x, r.size.y * 0.5 / half.y)
	m_per_px = clamp_mpp(maxf(need, 2.0 * NM / maxf(size.x, 1.0)))
	target_m_per_px = m_per_px
	_anchor_on = false


## Imagery level for a physical resolution: the level whose pixels are closest to the screen's.
static func level_for(phys_m_per_px: float, level_count: int) -> int:
	var l := floori(log(maxf(phys_m_per_px, 0.01) / LEVEL0_M_PER_PX) / log(2.0) + 0.5)
	return clampi(l, 0, maxi(level_count - 1, 0))


## A round scale-bar length (1, 2, 5 x 10^k nm) that is at most max_px long.
## Returns {nm, px, label}.
static func nice_scale(m_per_px_: float, max_px: float) -> Dictionary:
	var max_nm := max_px * m_per_px_ / NM
	var mag := pow(10.0, floorf(log(max_nm) / log(10.0)))
	var nm := mag
	for m in [5.0, 2.0, 1.0]:
		if m * mag <= max_nm:
			nm = m * mag
			break
	var label := ("%d nm" % int(round(nm))) if nm >= 1.0 else ("%.1f nm" % nm if nm >= 0.1 else "%.2f nm" % nm)
	return {"nm": nm, "px": nm * NM / m_per_px_, "label": label}


## The part of segment a-b inside rect (Liang-Barsky): empty if it misses, else [a', b'].
static func clip_segment(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var lo := rect.position
	var hi := rect.end
	for i in 2:
		var p := -d[i]
		var q := a[i] - lo[i]
		for pass_ in 2:
			if pass_ == 1:
				p = d[i]
				q = hi[i] - a[i]
			if is_zero_approx(p):
				if q < 0.0:
					return PackedVector2Array()
			else:
				var t := q / p
				if p < 0.0:
					if t > t1:
						return PackedVector2Array()
					t0 = maxf(t0, t)
				else:
					if t < t0:
						return PackedVector2Array()
					t1 = minf(t1, t)
	return PackedVector2Array([a + d * t0, a + d * t1])
