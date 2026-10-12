class_name ObstacleProbeWorld
extends RefCounted
## Helpers for tests/obstacle_probe.gd: teleport inside the real flight scene and wait for the
## streamed data, find forests / buildings through the game's own loaders, run scripted flights.

const KT := 0.514444
var probe: Node  # the probe node (get_tree)
var fn: FdmNode
var bld: Buildings
var trees: Trees
var terrain: TerrainQuadtree
var rows: Array[String] = []


func _init(p: Node, flight: Node) -> void:
	probe = p
	fn = flight.get_node("Fdm")
	bld = flight.get_node("Buildings")
	trees = flight.get_node("Trees")
	terrain = flight.get_node("Terrain")
	fn.paused = true


func row(case: String, crashed: bool, reason: String, note: String) -> void:
	var s := "ROW | %-44s | %-5s | %-52s | %s" % [case, "CRASH" if crashed else "no", reason, note]
	rows.append(s)
	print(s)


func frames(n: int) -> void:
	for i in n:
		await probe.get_tree().process_frame


func start_diag(p: Vector2) -> String:
	var tb := bld.building_top_at(p.x, p.y)
	var tt := trees.tree_top_at(p.x, p.y)
	return " [START INSIDE %s]" % ("a building" if tb > -INF else "a tree") if (tb > -INF or tt > -INF) else ""


func lc(e: float, n: float) -> int:
	return terrain.cache.landclass_at(e, n)


## Teleport the FDM and wait until land class and building collision exist there.
func teleport_wait(e: float, n: float, alt: float, hdg: float, kias: float, airborne := true) -> void:
	if airborne:
		fn.place_airborne(e, n, alt, hdg, kias)
	else:
		fn.place_on_ground(e, n, hdg)
	fn.paused = true
	var s := TerrainTileCache.TILE_SIZE_DEFAULT
	var tile := Vector2i(floori(e / s), floori(n / s))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await frames(1)
		var ready := lc(e, n) >= 0
		if FileAccess.file_exists(Paths.data("buildings").path_join("%d_%d.col" % [tile.x, tile.y])):
			ready = ready and not col_tile(tile).is_empty()
		if ready and Time.get_ticks_msec() - t0 > 1500:
			var dt := (Time.get_ticks_msec() - t0) / 1000.0
			if dt > 5.0:
				print("PROBE building collision / land class took %.1f s after arriving at %.0f %.0f" % [dt, e, n])
			return
	push_warning("probe: world not ready at %.0f %.0f" % [e, n])


func col_tile(tile: Vector2i) -> Dictionary:
	return bld.collision._tiles.get(tile, {})


func prefetch_lc(c: Vector2, half: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var missing := 0
		var y := c.y - half
		while y <= c.y + half:
			var x := c.x - half
			while x <= c.x + half:
				if lc(x, y) < 0:
					missing += 1
				x += 2000.0
			y += 2000.0
		if missing == 0:
			return
		await frames(1)


## [{poly, base, top, c, area}] of loaded collision buildings within r of (e, n).
func buildings_near(e: float, n: float, r: float, min_h := 0.0, min_area := 0.0, max_area := 1e12) -> Array:
	var out := []
	var s := TerrainTileCache.TILE_SIZE_DEFAULT
	var p := Vector2(e, n)
	for tx in range(floori((e - r) / s), floori((e + r) / s) + 1):
		for ty in range(floori((n - r) / s), floori((n + r) / s) + 1):
			var t: Dictionary = col_tile(Vector2i(tx, ty))
			for i in t.get("polys", []).size():
				var poly: PackedVector2Array = t.polys[i]
				var c := Vector2.ZERO
				for q in poly:
					c += q
				c /= poly.size()
				if c.distance_to(p) >= r or t.top[i] - t.base[i] < min_h:
					continue
				var area := 0.0
				for k in poly.size():
					area += poly[k].cross(poly[(k + 1) % poly.size()]) * 0.5
				area = absf(area)
				if area >= min_area and area <= max_area:
					out.append({"poly": poly, "base": t.base[i], "top": t.top[i], "c": c, "area": area})
	return out


## Eastward run of forest with land class in [lo, hi] on near-flat ground: [start Vector2] or [].
func find_forest(c: Vector2, half: float, run: float, lo: int, hi: int, flat := 6.0) -> Array:
	var y := c.y - half
	while y <= c.y + half:
		var x := c.x - half
		while x <= c.x + half:
			var ok := true
			var k := 0.0
			while k <= run:
				var v := lc(x + k, y)
				if v < lo or v > hi:
					ok = false
					break
				k += 20.0
			if ok and absf(terrain.height_at(x + run, y) - terrain.height_at(x, y)) < flat:
				return [Vector2(x, y)]
			x += 150.0
		y += 150.0
	return []


## Run scripted level flight east/west along a track; returns {crashed, reason, dist, note}.
func fly(case: String, start: Vector2, hdg: float, agl_or_alt: Callable, kias: float, dist: float, note := "", report := true, absolute := false) -> Dictionary:
	var gh := func(e: float, n: float) -> float: return terrain.height_at(e, n)
	var alt0: float = agl_or_alt.call(start.x, start.y) + (0.0 if absolute else gh.call(start.x, start.y))
	await teleport_wait(start.x, start.y, alt0, hdg, kias)
	note += start_diag(start)
	var fd := fn.fdm
	var pil := ObstacleProbePilot.new(fd, gh)
	pil.set_line(start, hdg)
	pil.speed_kt = kias
	pil.absolute = absolute
	var dir := Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg)))
	for i in int(dist / (kias * KT) / pil.DT) + 1:
		var ahead := Vector2(fd.pos_e, fd.pos_n) + dir * 40.0
		pil.agl_target = agl_or_alt.call(ahead.x, ahead.y)
		pil.fly()
		if fd.damage.crashed:
			break
	var d := Vector2(fd.pos_e - start.x, fd.pos_n - start.y).length()
	var r := {"crashed": fd.damage.crashed, "reason": fd.damage.crash_reason, "dist": d,
		"note": "%s | %.0f m, agl %.0f, ias %.0f" % [note, d, fd.agl, fd.cas / KT]}
	if report:
		row(case, r.crashed, r.reason, r.note)
	return r


func taxi(case: String, start: Vector2, hdg: float, kt: float, dist: float, note := "") -> Dictionary:
	await teleport_wait(start.x, start.y, 0.0, hdg, 0.0, false)
	var fd := fn.fdm
	note += start_diag(start)
	var pil := ObstacleProbePilot.new(fd, func(e: float, n: float) -> float: return terrain.height_at(e, n))
	pil.set_line(start, hdg)
	pil.speed_kt = kt
	fd.prop.rpm = 800.0
	fd.gear.brake_left = 0.0
	for i in int(dist / (kt * KT) / pil.DT) + 600:
		pil.taxi()
		if fd.damage.crashed or Vector2(fd.pos_e - start.x, fd.pos_n - start.y).length() > dist:
			break
	var d := Vector2(fd.pos_e - start.x, fd.pos_n - start.y).length()
	var gs := Vector2(fd.velocity_ned().x, fd.velocity_ned().y).length() / KT
	var r := {"crashed": fd.damage.crashed, "reason": fd.damage.crash_reason, "dist": d,
		"note": "%s | %.0f m, gs %.1f kt" % [note, d, gs]}
	row(case, r.crashed, r.reason, r.note)
	return r
