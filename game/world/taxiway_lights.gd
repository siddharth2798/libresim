class_name TaxiwayLights
extends RefCounted
## Taxiway lighting (pure layout): blue edge lights on both sides of every taxiway
## polyline (skipped at junctions, on runways and on aprons), green centreline lights on
## big airports with alternating green/yellow lead-on/off lights inside the runway strip,
## and at the holding positions red stop bars across the taxiway plus a flashing yellow
## pair of runway guard lights ("wig-wags").
## taxiways: [{width, pts: [[e, n, h], ...]}]; runways: AirportLights.describe() dicts.

const EDGE_STEP := 30.0
const CENTRE_STEP := 30.0
const LEAD_STEP := 15.0
const STRIP := 75.0  # lead-on/off zone: this far from the runway centreline
const APRON_R := 45.0  # no edge lights this close to a stand
const CELL := 50.0
const YELLOW := Color(1.0, 0.75, 0.12)

var _grid := {}  # Vector2i -> [[taxiway index, a, b, half width]]
var _runways: Array = []
var _stands: Array = []  # Vector2


func _init(taxiways: Array, runways: Array, stands: Array) -> void:
	_runways = runways
	for st in stands:
		_stands.append(Vector2(st.x, st.y))
	for ti in taxiways.size():
		var tw: Dictionary = taxiways[ti]
		var hw := minf(float(tw.width), 23.0) * 0.5
		for k in tw.pts.size() - 1:
			var a := Vector2(tw.pts[k][0], tw.pts[k][1])
			var b := Vector2(tw.pts[k + 1][0], tw.pts[k + 1][1])
			var lo := Vector2i(floori((minf(a.x, b.x) - hw) / CELL), floori((minf(a.y, b.y) - hw) / CELL))
			var hi := Vector2i(floori((maxf(a.x, b.x) + hw) / CELL), floori((maxf(a.y, b.y) + hw) / CELL))
			for cx in range(lo.x, hi.x + 1):
				for cy in range(lo.y, hi.y + 1):
					var key := Vector2i(cx, cy)
					if not _grid.has(key):
						_grid[key] = []
					_grid[key].append([ti, a, b, hw])


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


## True if p lies on a taxiway other than ti (within its half width + margin).
func on_other_taxiway(p: Vector2, ti: int, margin := 3.0) -> bool:
	for s in _grid.get(Vector2i(floori(p.x / CELL), floori(p.y / CELL)), []):
		if s[0] != ti and _seg_dist(p, s[1], s[2]) < s[3] + margin:
			return true
	return false


## Distance from p to the nearest runway centreline, and that runway's half width.
func runway_dist(p: Vector2) -> Vector2:
	var best := Vector2(INF, 0.0)
	for r in _runways:
		var d := _seg_dist(p, r.a, r.b)
		if d < best.x:
			best = Vector2(d, r.width * 0.5)
	return best


func near_stand(p: Vector2) -> bool:
	for s in _stands:
		if p.distance_squared_to(s) < APRON_R * APRON_R:
			return true
	return false


## Points every step metres along a polyline: [[Vector2 pos, Vector2 unit dir], ...].
static func resample(pts: Array, step: float, start := 0.0) -> Array:
	var out := []
	var carry := start
	for k in pts.size() - 1:
		var a := Vector2(pts[k][0], pts[k][1])
		var b := Vector2(pts[k + 1][0], pts[k + 1][1])
		var L := a.distance_to(b)
		if L < 0.01:
			continue
		var dir := (b - a) / L
		var t := carry
		while t <= L:
			out.append([a + dir * t, dir])
			t += step
		carry = t - L
	return out


## Edge and centreline lights of taxiway ti into s.
func taxiway(taxiways: Array, ti: int, centre: bool, hf: Callable, s: LightSet) -> void:
	var tw: Dictionary = taxiways[ti]
	var hw := minf(float(tw.width), 23.0) * 0.5 + 1.0
	for sm in resample(tw.pts, EDGE_STEP, EDGE_STEP * 0.5):
		var c: Vector2 = sm[0]
		var nrm := Vector2(sm[1].y, -sm[1].x)
		if near_stand(c):
			continue
		for sg in [-1.0, 1.0]:
			var p: Vector2 = c + nrm * hw * sg
			var rd := runway_dist(p)
			if rd.x < rd.y + 12.0 or on_other_taxiway(p, ti):
				continue
			s.add(p.x, p.y, hf.call(p.x, p.y) + 0.3, RunwayLightLayout.BLUE, Vector2.ZERO, 0.0, 0.0, false, 0.0, 0.6)
	if not centre:
		return
	var k := 0
	for sm in resample(tw.pts, LEAD_STEP, 2.0):
		var p: Vector2 = sm[0]
		var rd := runway_dist(p)
		if rd.x < rd.y - 1.0:
			continue  # on the runway itself
		var lead := rd.x < STRIP
		k += 1
		if not lead and k % int(CENTRE_STEP / LEAD_STEP) != 0:
			continue
		var col := (YELLOW if k % 2 == 0 else RunwayLightLayout.GREEN) if lead else RunwayLightLayout.GREEN
		s.add(p.x, p.y, hf.call(p.x, p.y) + 0.08, col, sm[1], 2.0, 0.3, true, 0.0, 0.55)


## Nearest taxiway segment to p within max_d: [unit dir, half width] or [].
func nearest_segment(p: Vector2, max_d := 40.0) -> Array:
	var best := []
	var bd := max_d
	var c := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	for cx in range(c.x - 1, c.x + 2):
		for cy in range(c.y - 1, c.y + 2):
			for s in _grid.get(Vector2i(cx, cy), []):
				var d := _seg_dist(p, s[1], s[2])
				if d < bd and s[1] != s[2]:
					bd = d
					best = [(s[2] - s[1]).normalized(), s[3]]
	return best


## Stop bar + runway guard lights at hold point p; returns the number of stop-bar lights.
func hold(p: Vector2, hf: Callable, stop: LightSet) -> int:
	var seg := nearest_segment(p)
	if seg.is_empty():
		return 0
	var t: Vector2 = seg[0]
	var hw: float = seg[1]
	# beam away from the runway: toward the aircraft waiting at the hold
	var rc := Vector2.ZERO
	var bd := INF
	for r in _runways:
		var q := Geometry2D.get_closest_point_to_segment(p, r.a, r.b)
		if p.distance_to(q) < bd:
			bd = p.distance_to(q)
			rc = q
	var f := -t if t.dot(rc - p) > 0.0 else t
	var across := Vector2(t.y, -t.x)
	var n := 0
	var w := -hw
	while w <= hw + 0.01:
		var q: Vector2 = p + across * w
		stop.add(q.x, q.y, hf.call(q.x, q.y) + 0.1, RunwayLightLayout.RED, f, 3.0, 0.05, false, 0.0, 0.8)
		n += 1
		w += 3.0
	for k in 2:  # wig-wags: alternate at 1 Hz, just outside the taxiway edge
		var g: Vector2 = p + across * (hw + 3.0) * (1.0 if k == 0 else -1.0) - f * 1.0
		stop.add(g.x, g.y, hf.call(g.x, g.y) + 0.8, YELLOW, f, 3.0, 0.05, false, 2.0 + k * 0.5, 1.2)
	return n
