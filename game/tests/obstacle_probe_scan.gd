class_name ObstacleProbeScan
extends RefCounted
## False-positive scan for tests/obstacle_probe.gd: put the aircraft hull at every stand, along every
## pushback path, every taxiway edge and every runway of every airport with ground-ops data, and
## count the poses where it already overlaps a solid. Normal operations must give zero.

var w: ObstacleProbeWorld
var fn: FdmNode
var ops: AirportOps
var airports: AirportBuilder
var raw := true  # every overlap; false: after the corridor / forgiveness rules


func _init(world: ObstacleProbeWorld, o: AirportOps, ab: AirportBuilder) -> void:
	w = world
	fn = world.fn
	ops = o
	airports = ab


func _hit(e: float, n: float, hdg_rad: float, parked := false) -> Dictionary:
	var f := fn.fdm
	f.set_on_ground(n, e, hdg_rad)
	f.obstacle_collision._ignored.clear()
	f.obstacle_collision._last = Vector2(f.pos_e, f.pos_n) if parked else Vector2(INF, INF)
	return f.obstacle_collision.check(f, raw, not raw and not parked)


func run(only_icao := "", raw_mode := true) -> void:
	raw = raw_mode
	for icao in ops.data:
		if only_icao != "" and icao != only_icao:
			continue
		var a: Dictionary = ops.data[icao]
		if a.taxi.nodes.is_empty() and a.stands.is_empty():
			continue
		var c: Array = a.taxi.nodes.values()[0] if not a.taxi.nodes.is_empty() else [a.stands[0].x, a.stands[0].y]
		await w.teleport_wait(c[0], c[1], 0.0, 0.0, 0.0, false)
		await w.frames(150)
		var stat := {"stand": [0, {}], "push": [0, {}], "taxi": [0, {}], "runway": [0, {}]}
		var first := {}
		for s in a.stands:
			var h0 := deg_to_rad(float(s.heading_deg))
			_pose(stat, first, "stand", s.x, s.y, h0, "stand %s" % s.ref)
			for side in [1.0, -1.0]:
				var d := 0.0
				while d < PushbackPath.length():
					var p := PushbackPath.pose(Vector2(s.x, s.y), h0, side, d)
					_pose(stat, first, "push", p[0].x, p[0].y, p[1], "pushback from %s (side %+.0f, %.0f m)" % [s.ref, side, d])
					d += 4.0
		for e in a.taxi.edges:
			var p0: Array = a.taxi.nodes[e[0]]
			var p1: Array = a.taxi.nodes[e[1]]
			var d := Vector2(p1[0] - p0[0], p1[1] - p0[1])
			var hd := atan2(d.x, d.y)
			var k := 0.0
			while k <= d.length():
				var p := Vector2(p0[0], p0[1]) + d.normalized() * k
				_pose(stat, first, "runway" if e[4] == "runway" else "taxi", p.x, p.y, hd, "%s edge %s (%.0f m)" % ["runway" if e[4] == "runway" else "taxiway", str(e[2]), k])
				_pose(stat, first, "runway" if e[4] == "runway" else "taxi", p.x, p.y, hd + PI, "%s edge %s reversed" % ["runway" if e[4] == "runway" else "taxiway", str(e[2])])
				k += 10.0
		for r in airports.data.runways:
			if r.airport != icao:
				continue
			var p0 := Vector2(r.ends[0].x, r.ends[0].y)
			var p1 := Vector2(r.ends[1].x, r.ends[1].y)
			var hd := atan2(p1.x - p0.x, p1.y - p0.y)
			var k := 0.0
			while k <= p0.distance_to(p1):
				var p := p0 + (p1 - p0).normalized() * k
				_pose(stat, first, "runway", p.x, p.y, hd, "runway %s (%.0f m)" % [r.ends[0].ident, k])
				k += 20.0
		var parts := []
		for k in stat:
			var d: Dictionary = stat[k][1]
			var kinds := {}
			for key in d:
				kinds[key.get_slice(" @", 0)] = kinds.get(key.get_slice(" @", 0), 0) + d[key]
			parts.append("%s %d/%d poses: %s" % [k, d.size(), stat[k][0], str(kinds).replace("\n", "")])
		var line := "%s: %d stands, %d ops solids | %s" % [icao, a.stands.size(), ObstacleRegistry.count("ops:" + icao), " | ".join(parts)]
		w.row("scan " + icao, false, "-", line)
		for k in first:
			for lab in first[k]:
				print("    %s conflict: %s" % [k, first[k][lab]])


func _pose(stat: Dictionary, first: Dictionary, kind: String, e: float, n: float, hdg: float, what: String) -> void:
	var h := _hit(e, n, hdg, kind == "stand")
	stat[kind][0] += 1
	if h.is_empty():
		return
	var key := "%s @%.0f,%.0f" % [h.label, e, n]
	stat[kind][1][key] = stat[kind][1].get(key, 0) + 1
	if not first.has(kind):
		first[kind] = {}
	if not first[kind].has(h.label):
		first[kind][h.label] = "%s: the %s hit %s at %.0f %.0f" % [what, h.part, h.label, e, n]
