class_name AirportGroups
extends RefCounted
## What AirportBuilder builds, one group per airport: its runways, its taxiways (OSM taxiways carry no airport, so each goes
## to the airport of the nearest runway; far from every runway they form a cell group of their own) and the lead-on lines
## over its runways. Each group has a bounding circle (centre, radius) and a visible size, which decide when it is
## built near the aircraft and freed far from it: a group is wanted while the camera is within range_m() of its circle,
## range_m() = VisRanges.end_for(size) x the preset's detail x the zoom, the draw distance of anything that large
## (world/vis_ranges.gd: at least 3 px on a 1080p frame at the reference field of view). size = sqrt(length x width) of the
## airport's longest runway. Freed again only beyond range_m() x HYSTERESIS, so nothing flickers at the boundary.
## --no-vis-ranges (before / after measurements) makes every group wanted at all times, as it was before.
## Pure data: nothing here touches the scene.

const ORPHAN_M := 3000.0  # a taxiway farther than this from every runway is not part of an airport
const CELL_M := 6000.0  # orphan taxiways are grouped into cells of this size
const HYSTERESIS := 1.3  # freed beyond range x this
const ORPHAN_WIDTH := 15.0


## Groups of runways.json (data: {runways, taxiways}): [{key, runways, taxis, leads, centre, radius, h, size}].
static func make(data: Dictionary) -> Array:
	var groups := {}
	for r in data.runways:
		var key := str(r.airport)
		if not groups.has(key):
			groups[key] = {"key": key, "runways": [], "taxis": [], "leads": [], "centre": Vector2.ZERO, "radius": 0.0, "h": 0.0, "size": 0.0}
		groups[key].runways.append(r)
	var boxes := []  # Rect2 of each taxiway's points (parallel to data.taxiways), for the lead-on filter
	for tw in data.taxiways:
		var pts: Array[Vector2] = []
		for p in tw.pts:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() < 2:
			boxes.append(Rect2(1e12, 1e12, 0.0, 0.0))  # nothing to draw; far from every runway
			continue
		var key := _owner(data.runways, pts)
		if not groups.has(key):
			groups[key] = {"key": key, "runways": [], "taxis": [], "leads": [], "centre": Vector2.ZERO, "radius": 0.0, "h": 0.0, "size": 0.0}
		groups[key].taxis.append(tw)
		boxes.append(_bounds(pts))
	for r in data.runways:
		groups[str(r.airport)].leads.append_array(lead_ons(r, data.taxiways, boxes))
	var out := []
	for k in groups:
		_measure(groups[k])
		out.append(groups[k])
	return out


## The airport a taxiway belongs to: its nearest runway's, or a cell key beyond ORPHAN_M.
static func _owner(runways: Array, pts: Array[Vector2]) -> String:
	var best := INF
	var key := ""
	var probes := [pts[0], pts[pts.size() >> 1], pts[-1]]
	for r in runways:
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		for p in probes:
			var c := Geometry2D.get_closest_point_to_segment(p, a, b)
			var d: float = p.distance_to(c)
			if d < best:
				best = d
				key = str(r.airport)
	if best <= ORPHAN_M:
		return key
	return "cell:%d:%d" % [floori(pts[0].x / CELL_M), floori(pts[0].y / CELL_M)]


static func _bounds(pts: Array[Vector2]) -> Rect2:
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	return box


## Centre, radius, ground height and visible size of a group from everything in it.
static func _measure(g: Dictionary) -> void:
	var all: Array[Vector2] = []
	var hs := 0.0
	var hn := 0
	var width_len := 0.0
	var longest := 0.0
	for r in g.runways:
		for e in r.ends:
			all.append(Vector2(e.x, e.y))
			hs += float(e.get("h", 0.0))
			hn += 1
		if float(r.length) * float(r.width) > width_len:
			width_len = float(r.length) * float(r.width)
		longest = maxf(longest, float(r.length))
	for tw in g.taxis:
		for p in tw.pts:
			all.append(Vector2(p[0], p[1]))
	if all.is_empty():
		return
	var box := _bounds(all)
	g.centre = box.get_center()
	var rad := 0.0
	for p in all:
		rad = maxf(rad, g.centre.distance_to(p))
	g.radius = rad + 30.0
	g.h = hs / float(hn) if hn > 0 else 0.0
	g.size = sqrt(width_len) if width_len > 0.0 else sqrt(maxf(box.size.x, box.size.y) * ORPHAN_WIDTH)


## The yellow lead-on line over runway r: the part of each taxiway inside the runway strip, as [Vector2] polylines.
## OSM taxiways end on the runway centre line, but the runway surface hides that last stretch. boxes: the
## Rect2 of its points, parallel to taxiways (skips taxiways nowhere near).
static func lead_ons(r: Dictionary, taxiways: Array, boxes := []) -> Array:
	var out := []
	var a := Vector2(r.ends[0].x, r.ends[0].y)
	var b := Vector2(r.ends[1].x, r.ends[1].y)
	var u := (b - a).normalized()
	var hw := float(r.width) * 0.5
	var length := a.distance_to(b)
	var near := Rect2(a, Vector2.ZERO).expand(b).grow(hw + 60.0)
	for i in taxiways.size():
		var tw: Dictionary = taxiways[i]
		if not boxes.is_empty() and not near.intersects(boxes[i]):
			continue
		var run: Array[Vector2] = []
		var prev := Vector2.INF
		for p in tw.pts:
			var v := Vector2(p[0], p[1])
			var along := (v - a).dot(u)
			if absf((v - a).cross(u)) < hw + 0.5 and along > -2.0 and along < length + 2.0:
				if run.is_empty() and prev != Vector2.INF:
					run.append(prev)  # the last point outside: the line enters the runway from there
				run.append(v)
			elif not run.is_empty():
				run.append(v)  # first point past the strip: the line crosses it
				break
			prev = v
		if run.size() >= 2:
			out.append(run)
	return out


## Metres from camera cam (ENU x, y, up) to the group's bounding sphere (0 inside it).
static func excess(g: Dictionary, cam: Vector3) -> float:
	var dh := Vector2(cam.x, cam.y).distance_to(g.centre)
	return maxf(sqrt(dh * dh + (cam.z - g.h) * (cam.z - g.h)) - g.radius, 0.0)


## Build range (m) of a group now; 0 = always (vis ranges off).
static func range_m(g: Dictionary) -> float:
	return VisRanges.effective(VisRanges.end_for(g.size))


## What to do: excess[i] from excess(), ranges[i] from range_m(), built[i] has nodes (or is being cut). Returns
## {build: indices wanted and not built, nearest first, free: indices built beyond range x HYSTERESIS}.
static func plan(excesses: Array, ranges: Array, built: Array) -> Dictionary:
	var build := []
	var free := []
	for i in excesses.size():
		var rng: float = ranges[i]
		if built[i]:
			if rng > 0.0 and excesses[i] > rng * HYSTERESIS:
				free.append(i)
		elif rng <= 0.0 or excesses[i] < rng:
			build.append(i)
	build.sort_custom(func(a, b): return excesses[a] < excesses[b])
	return {"build": build, "free": free}
