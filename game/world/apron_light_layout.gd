class_name ApronLightLayout
extends RefCounted
## Where the apron floodlights of one airport stand and what they aim at (pure: no nodes). Three kinds:
##   "facade": floods on the terminal facade above a contact stand (a stand with a jetbridge and a gate point
##             ahead of its nose), aimed back at the parked aircraft; no pole, no collision.
##   "mast":   high masts (12-30 m, taller on bigger airports) on the head-of-stand line between airliner stands
##             (remote stands, contact stands without a facade), every ~2 stands.
##   "pole":   10 m pole lights on GA aprons (stands "GA..."), every few tie-downs.
## Every stand ends up within reach of a light where a clear spot exists: no MIN_STANDS cliff. A spot is clear
## when it is outside every ObstacleRegistry corridor (stands with their pushback swing, taxiways, runway strips),
## outside the parking box of every stand (sized by the stand spacing, so an airliner on a neighbouring stand
## never meets a mast), away from jetways, and low enough for its distance to a runway (a mast is no taller
## than (distance from the runway edge - 30 m) / 4).
## Each light has banks (one per aim direction); a bank is one real SpotLight near the camera
## (ApronLamps) or one fake pool on the ground (ApronFloodlights).
## Lamp colour: one per airport (a mix of warm and cool pools overlapping reads as coloured blotches): ops
## "apron_lamps" ("led" | "hps", via the data fixups) else a hash of the ICAO code (newer LED neutral white,
## older high-pressure sodium soft warm white).

const LED := Color(1.0, 0.94, 0.86)  # ~4000 K LED (neutral white)
const HPS := Color(1.0, 0.83, 0.62)  # high-pressure sodium, toned down (a saturated orange goes pink in AgX)
const FACADE_H := 18.0  # floods on the terminal roof edge
const POLE_H := 10.0
const MIN_H := 8.0
const BIG := 20  # airliner stands for the tallest masts
## kind -> [reach (m: a stand within this of the light counts as lit), cone half-angle (deg)]
const KIND := {"mast": [70.0, 52.0], "pole": [30.0, 60.0], "facade": [45.0, 42.0]}


## Light list for one airport: [{p: Vector2 ENU, h: m above the ground, kind, col: Color, banks: [{aim: Vector2,
## heads: int, half_deg: float}]}]. stands: airport_ops.json stands; ops: the airport's whole entry (gates,
## jetbridges, jetlinks, apron_lamps); runways: its runways.json entries.
static func build(stands: Array, runways: Array = [], ops: Dictionary = {}, icao := "") -> Array:
	if stands.is_empty():
		return []
	var sp := spacings(stands)
	var jet := jet_segments(ops)
	var lamps := lamp_type(icao, ops, stands.size())
	var out := []
	var classes := {"mast": [], "pole": []}
	for i in stands.size():
		var s: Dictionary = stands[i]
		var f := facade(s, ops.get("gates", []), jet)
		if f == Vector2.INF:
			classes["pole" if is_ga(s) else "mast"].append(i)
			continue
		var near := out.filter(func(m): return m.p.distance_to(f) < 22.0)  # neighbouring gates share a flood
		if near.is_empty():
			out.append({"p": f, "h": FACADE_H, "kind": "facade", "stands": [i]})
		else:
			near[0].stands.append(i)
	var airliners: int = classes.mast.size() + out.size()
	var mast_h := 28.0 if airliners >= BIG else (20.0 if airliners >= 6 else 15.0)
	for kind in ["mast", "pole"]:
		var want: float = mast_h if kind == "mast" else POLE_H
		var reach: float = KIND[kind][0]
		for i in classes[kind]:
			var s: Dictionary = stands[i]
			if _near_light(out, Vector2(s.x, s.y), reach * 0.8, kind):
				continue
			for c in candidates(s, sp[i], kind):
				var h := minf(want, max_height(c, runways))
				if h >= MIN_H and clear(c, stands, sp, jet) and not _near_light(out, c, reach * 0.7):
					out.append({"p": c, "h": h, "kind": kind, "stands": []})
					break
	var on_facade := {}
	for m in out:
		for i in m.stands:
			on_facade[i] = true
	for i in stands.size():  # every other stand to its nearest light in reach
		if on_facade.has(i):
			continue
		var p := Vector2(stands[i].x, stands[i].y)
		var best := -1
		var bd := INF
		for k in out.size():
			var d: float = p.distance_to(out[k].p)
			if out[k].kind != "facade" and d < KIND[out[k].kind][0] * 1.2 and d < bd:
				bd = d
				best = k
		if best >= 0:
			out[best].stands.append(i)
	for k in out.size():
		var m: Dictionary = out[k]
		m.col = _colour(lamps, m.p)
		m.banks = banks(m, stands)
		m.erase("stands")
	return out.filter(func(m): return not m.banks.is_empty())


## GA tie-downs (light poles, not masts).
static func is_ga(s: Dictionary) -> bool:
	return str(s.get("ref", "")).begins_with("GA")


static func lamp_type(icao: String, ops: Dictionary, n_stands: int) -> String:
	var t := str(ops.get("apron_lamps", ""))
	if t in ["led", "hps"]:
		return t
	var k := absi(hash(icao)) % 4
	if n_stands >= BIG:  # the big airports have mostly been relit with LED
		return ["led", "led", "led", "hps"][k]
	return ["hps", "hps", "led", "led"][k]


static func _colour(lamps: String, _p: Vector2) -> Color:
	return LED if lamps == "led" else HPS


## Distance between a stand and its nearest neighbour (m), clamped: an airliner stand is wingspan + ~8 m
## wide, a GA tie-down ~15 m.
static func spacings(stands: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in stands.size():
		var p := Vector2(stands[i].x, stands[i].y)
		var bd := 90.0
		for j in stands.size():
			if j != i:
				bd = minf(bd, p.distance_to(Vector2(stands[j].x, stands[j].y)))
		out.append(clampf(bd, 12.0 if is_ga(stands[i]) else 30.0, 90.0))
	return out


## Candidate light spots for a stand: on the head-of-stand line (ahead of the nose) between this stand and
## the next, then straight ahead, then further out; last behind the tail.
static func candidates(s: Dictionary, sp: float, kind: String) -> Array:
	var hd := deg_to_rad(float(s.heading_deg))
	var f := Vector2(sin(hd), cos(hd))
	var r := Vector2(f.y, -f.x)
	var c := Vector2(s.x, s.y)
	var nose := sp * 0.55 + (8.0 if kind == "mast" else 4.0)
	var out := []
	for fwd in [nose, nose + 10.0, nose + 22.0, -(nose + 16.0)]:
		for lat in [sp * 0.5, -sp * 0.5, 0.0]:
			out.append(c + f * fwd + r * lat)
	return out


## Tallest mast allowed at p by the runways (obstacle surfaces, roughly): (distance from the edge - 30) / 4,
## and nothing within 300 m beyond a runway end closer than 60 m to its extended centreline.
static func max_height(p: Vector2, runways: Array) -> float:
	var h := 40.0
	for rw in runways:
		var a := Vector2(rw.ends[0].x, rw.ends[0].y)
		var b := Vector2(rw.ends[1].x, rw.ends[1].y)
		var u := (b - a).normalized()
		var along := (p - a).dot(u)
		var side := absf((p - a).cross(u)) - float(rw.width) * 0.5
		if along < -300.0 or along > a.distance_to(b) + 300.0:
			continue
		if (along < 0.0 or along > a.distance_to(b)) and side < 60.0:
			return 0.0
		h = minf(h, (side - 30.0) / 4.0)
	return h


## p is clear: not in a corridor, nor in any stand's parking box, nor within 7 m of a jetway.
static func clear(p: Vector2, stands: Array, sp: PackedFloat32Array, jet: Array) -> bool:
	if ObstacleRegistry.overlaps_corridor(ObstacleShapes.box(p, 1.5, 1.5, 0.0, 0.0, 0.0, "")):
		return false
	for i in stands.size():
		var s: Dictionary = stands[i]
		var d := p - Vector2(s.x, s.y)
		if d.length() > 120.0:
			continue
		var hd := deg_to_rad(float(s.heading_deg))
		var f := Vector2(sin(hd), cos(hd))
		var fwd := d.dot(f)
		if absf(d.dot(Vector2(f.y, -f.x))) < sp[i] * 0.5 - 1.0 and fwd < sp[i] * 0.5 + 4.0 and fwd > -(sp[i] * 0.5 + 8.0):
			return false
	for sg in jet:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])) < 7.0:
			return false
	return true


## The facade above a contact stand: the gate point 12-80 m ahead of it (within 45 m to the side), moved onto
## the stand's centre line; INF when the stand has no jetbridge or no gate point ahead.
static func facade(s: Dictionary, gates: Array, jet: Array) -> Vector2:
	if not s.get("jetbridge", false) or (gates.is_empty() and jet.is_empty()):
		return Vector2.INF
	var hd := deg_to_rad(float(s.heading_deg))
	var f := Vector2(sin(hd), cos(hd))
	var c := Vector2(s.x, s.y)
	var best := INF
	var pts := []
	for g in gates:
		pts.append(Vector2(g.x, g.y))
	for sg in jet:
		pts.append_array(sg)
	for q in pts:
		var d: Vector2 = q - c
		var fwd := d.dot(f)
		if fwd > 12.0 and fwd < 80.0 and absf(d.dot(Vector2(f.y, -f.x))) < 45.0:
			best = minf(best, fwd)
	return Vector2.INF if best == INF else c + f * (best + 3.0)


## Jetway and fixed-link segments [[a, b]] (ENU) of an airport.
static func jet_segments(ops: Dictionary) -> Array:
	var out := []
	for jb in ops.get("jetbridges", []):
		var pts: Array = jb.get("pts", [])
		for k in pts.size() - 1:
			out.append([Vector2(pts[k][0], pts[k][1]), Vector2(pts[k + 1][0], pts[k + 1][1])])
	for jl in ops.get("jetlinks", []):
		out.append([Vector2(jl.a[0], jl.a[1]), Vector2(jl.b[0], jl.b[1])])
	return out


static func _near_light(lights: Array, p: Vector2, r: float, kind := "") -> bool:
	for m in lights:
		if (kind == "" or m.kind == kind or m.kind == "mast") and p.distance_to(m.p) < r:
			return true
	return false


## Banks of one light: its stands grouped by direction (50 deg sectors), each aimed at the middle of its stands
## (pulled toward the light so the far edge of the stand is in the cone), 2-4 heads. A light with no stand
## (should not happen) aims nowhere and is dropped.
static func banks(m: Dictionary, stands: Array) -> Array:
	var dirs := []
	for i in m.stands:
		var q := Vector2(stands[i].x, stands[i].y)
		if m.kind == "facade":  # the aircraft body is behind the door point the gate stand marks
			var hd := deg_to_rad(float(stands[i].heading_deg))
			q -= Vector2(sin(hd), cos(hd)) * 12.0
		dirs.append([(q - m.p).angle(), q])
	dirs.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	var grp := []
	for d in dirs + [null]:
		if d != null and (grp.is_empty() or absf(angle_difference(grp[0][0], d[0])) < deg_to_rad(50.0)):
			grp.append(d)
			continue
		if not grp.is_empty():
			var c := Vector2.ZERO
			for g in grp:
				c += g[1]
			c /= grp.size()
			var aim: Vector2 = m.p + (c - m.p) * 0.85
			if aim.distance_to(m.p) < 6.0:  # a stand right under the light: aim a little out
				aim = m.p + Vector2.from_angle(grp[0][0]) * 6.0
			out.append({"aim": aim, "heads": clampi(grp.size() + 1, 2, 4), "half_deg": float(KIND[m.kind][1])})
		grp = [d] if d != null else []
	return out
