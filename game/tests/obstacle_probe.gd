extends Node
## Probe: do collisions with trees, buildings, terminals, jetways, vehicles register in the
## REAL loaded world? Loads world/flight.tscn, teleports the aircraft, waits for trees / building
## collision data to stream in, then flies / taxis scripted runs (obstacle_probe_pilot.gd) by stepping
## the FDM directly (faster than real time) and prints one ROW per case.
##   godot --headless --path game res://tests/obstacle_probe.tscn [-- --only=mirror,bury,forest,city,taxi,airport,corridor,fast,scan --icao=VABB]
## Needs data/processed (not part of the unit suite). Cases are described in docs/USAGE.md (crash model).

var f: Node
var w: ObstacleProbeWorld
var apts := {}  # icao -> Vector2 ENU
var only := []
var icao := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		if a.begins_with("--icao="):
			icao = a.substr(7)
	Engine.max_fps = 0
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	for i in 3:
		await get_tree().process_frame
	w = ObstacleProbeWorld.new(self, f)
	for a in Paths.load_json("airports.json"):
		apts[a.icao if a.icao != "" else a.ident] = Vector2(a.x, a.y)
	for k in ["mirror", "bury", "forest", "city", "taxi", "airport", "corridor", "fast", "scan", "perf", "ops"]:
		if only.is_empty() or only.has(k):
			await call("_case_" + k)
	print("---- PROBE SUMMARY ----")
	for r in w.rows:
		print(r)
	get_tree().quit()


## Is a 14 m wide corridor free of any solid for `len` m from p along dir?
func _clear(p: Vector2, dir: Vector2, len: float) -> bool:
	var side := Vector2(dir.y, -dir.x)
	var k := 0.0
	while k <= len:
		for off in [-7.0, 0.0, 7.0]:
			var q: Vector2 = p + dir * k + side * off
			if w.bld.building_top_at(q.x, q.y) > -INF or w.trees.tree_top_at(q.x, q.y) > -INF:
				return false
		k += 2.5
	return true


# ---- trees: do collision trees sit where the rendered trees are? -------------------------

func _chunk_trees(smp: TreeSampler, c: Vector2) -> PackedFloat32Array:
	var tm := w.terrain.cache.tmeta
	var k := Vector2i(floori(c.x / Trees.CHUNK), floori(c.y / Trees.CHUNK))
	var src := tm.tex_source(0, floori(k.x * Trees.CHUNK / tm.tile_size_m), floori(k.y * Trees.CHUNK / tm.tile_size_m), TerrainMeta.HAS_LC)
	if src == TerrainMeta.NONE:
		return PackedFloat32Array()
	return smp.build(k.x * Trees.CHUNK, k.y * Trees.CHUNK, Trees.CHUNK, Trees.PX, src, tm.level_size(src.x), w.trees.density_scale)


func _case_mirror() -> void:
	var smp := TreeSampler.new(w.terrain.cache)
	for q in [["NE (E>0 N>0)", Vector2(4850, 9650)], ["NW (E<0 N>0, Mumbai side)", Vector2(-14950, 2900)],
			["SE (E>0 N<0, Pune side)", Vector2(14900, -21700)], ["SW (E<0 N<0)", Vector2(-17950, -22000)],
			["Kochi corridor", apts["VOCI"] + Vector2(3000, 3000)]]:
		var c: Vector2 = q[1]
		await w.teleport_wait(c.x, c.y, 600.0, 90.0, 80.0)
		await w.prefetch_lc(c, 3000.0)
		var buf := _chunk_trees(smp, c)
		var n := buf.size() / 16
		var hit := 0
		var k := Vector2i(floori(c.x / Trees.CHUNK), floori(c.y / Trees.CHUNK))
		for i in n:
			var o := i * 16
			var top := w.trees.tree_top_at(buf[o + 3] + k.x * Trees.CHUNK, -buf[o + 11] + k.y * Trees.CHUNK)
			if top > -INF and absf(top - (buf[o + 7] + 0.3 + buf[o + 5] * 0.9)) < 0.5:
				hit += 1
		w.row("tree mirror " + q[0], false, "-", "%d rendered trees: %d (%.0f%%) have a collision tree at their position" % [n, hit, 100.0 * hit / maxf(n, 1)])


## Collision buildings whose roof is below the terrain surface (buildings made from an older DEM than the runtime terrain).
func _case_bury() -> void:
	for q in [["VABB", apts["VABB"]], ["VAPO", apts["VAPO"]], ["VOCI", apts["VOCI"]], ["Mumbai", Vector2(-60300.0, 25262.0)]]:
		var c: Vector2 = q[1]
		await w.teleport_wait(c.x, c.y, 300.0, 90.0, 80.0)
		await w.frames(60)
		var bs := w.buildings_near(c.x, c.y, 3000.0)
		var buried := 0
		var floating := 0
		var worst := 0.0
		for b in bs:
			var gmax := -INF
			var gmin := INF
			for p in b.poly:
				var g := w.terrain.height_at(p.x, p.y)
				gmax = maxf(gmax, g)
				gmin = minf(gmin, g)
			if b.top < gmax:
				buried += 1
				worst = maxf(worst, gmax - b.top)
			if b.base > gmin + 3.0:
				floating += 1
		w.row("buildings vs terrain " + q[0], false, "-", "%d footprints within 3 km: %d with the roof below the terrain (worst %.0f m), %d with base > ground+3 m" % [bs.size(), buried, worst, floating])


# ---- (a) forest ----------------------------------------------------------------------------

## Rendered trees (TreeSampler = what is on screen) the wings sweep through: ground truth for sparse forest.
func _truth(smp: TreeSampler, start: Vector2, hdg: float, dist: float, agl: float) -> int:
	var dir := Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg)))
	var side := Vector2(dir.y, -dir.x)
	var seen := {}
	var cnt := 0
	var s := 0.0
	while s <= dist:
		var p := start + dir * s
		var k := Vector2i(floori(p.x / Trees.CHUNK), floori(p.y / Trees.CHUNK))
		if not seen.has(k):
			seen[k] = _chunk_trees(smp, p)
		s += Trees.CHUNK * 0.5
	for k in seen:
		var buf: PackedFloat32Array = seen[k]
		for i in buf.size() / 16:
			var o := i * 16
			var tp := Vector2(buf[o + 3] + k.x * Trees.CHUNK, -buf[o + 11] + k.y * Trees.CHUNK)
			var along := (tp - start).dot(dir)
			var cross := absf((tp - start).dot(side))
			var r := Vector2(buf[o], buf[o + 8]).length() * 0.5
			var top := buf[o + 7] + buf[o + 5]
			if along > 0.0 and along < dist and cross < 5.4 + r and top > w.terrain.height_at(tp.x, tp.y) + agl - 0.5:
				cnt += 1
	return cnt


func _case_forest() -> void:
	var smp := TreeSampler.new(w.terrain.cache)
	var quads := [["NE", Vector2(12000, 12000)], ["NW Mumbai side", Vector2(-12000, 12000)], ["SE Pune side", Vector2(12000, -12000)],
		["SW", Vector2(-12000, -12000)], ["Kochi corridor", apts["VOCI"]]]
	for q in quads:
		var c: Vector2 = q[1]
		await w.teleport_wait(c.x, c.y, 600.0, 90.0, 80.0)
		await w.prefetch_lc(c, 12000.0)
		var dense: Array = w.find_forest(c, 10000.0, 600.0, 140, 200)
		if dense.is_empty():
			w.row("dense forest " + q[0], false, "-", "no dense forest found (lc >= 140 over 600 m)")
		else:
			var fs: Vector2 = dense[0] - Vector2(300.0, 0.0)
			for agl in [6.0, 10.0, 12.0]:
				await w.fly("dense forest 80kt agl %.0f m %s" % [agl, q[0]], fs - Vector2(200.0, 0.0), 90.0, func(e, n): return agl, 80.0, 1100.0, "forest at %.0f %.0f" % [fs.x, fs.y])
			await w.taxi("taxi into dense forest 8kt " + q[0], fs - Vector2(100.0, 0.0), 90.0, 8.0, 400.0, "forest at %.0f %.0f" % [fs.x, fs.y])
		var sparse: Array = dense
		if sparse.is_empty():
			continue
		var ss: Vector2 = sparse[0] + Vector2(300.0, 0.0)
		w.trees.density_scale = 0.3  # sparse (the low graphics preset is 0.5)
		for agl in [4.0, 7.0]:
			var truth := _truth(smp, ss, 90.0, 800.0, agl)
			var r: Dictionary = await w.fly("sparse trees 80kt agl %.0f m %s" % [agl, q[0]], ss, 90.0, func(e, n): return agl, 80.0, 800.0, "wings sweep %d rendered trees" % truth, false)
			w.row("sparse trees (density 0.3) 80kt agl %.0f m %s" % [agl, q[0]], r.crashed, r.reason, "%s%s" % [r.note, "  <-- MISSED %d trees" % truth if not r.crashed and truth > 0 else ""])
		w.trees.density_scale = 1.0


# ---- (b) city buildings ------------------------------------------------------------------

func _case_city() -> void:
	await _city("Mumbai", Vector2(-60300.0, 25262.0))
	await _city("Pune", apts["VAPO"] + Vector2(-4000.0, 3000.0))


func _city(name: String, c: Vector2) -> void:
	await w.teleport_wait(c.x, c.y, 300.0, 90.0, 80.0)
	await w.frames(60)
	var big := w.buildings_near(c.x, c.y, 2500.0, 12.0, 400.0)
	if big.is_empty():
		w.row("city " + name, false, "-", "no loaded collision buildings (%d col tiles)" % w.bld.collision.tiles_loaded())
		return
	var tall: Dictionary = {}
	big.sort_custom(func(a, b): return a.top > b.top)
	for b in big.slice(0, 40):
		if _clear(b.c - Vector2(300.0, 0.0), Vector2(1, 0), 280.0):
			tall = b
			break
	if tall.is_empty():
		tall = big[0]
	var bc: Vector2 = tall.c
	for dz in [-4.0, 0.6, 2.5]:
		await w.fly("%s nose-on roof%+.1f m" % [name, dz], bc - Vector2(500.0, 0.0), 90.0, func(e, n): return tall.top + dz, 80.0, 700.0, "top %.0f m, h %.0f" % [tall.top, tall.top - tall.base], true, true)
	var north := -INF
	for q in tall.poly:
		north = maxf(north, (q as Vector2).y)
	await w.fly("%s wingtip clip (3 m in)" % name, Vector2(bc.x - 500.0, north + 2.5), 90.0, func(e, n): return tall.top - 4.0, 80.0, 700.0, "track 2.5 m N of the building's N-most vertex", true, true)
	var small := w.buildings_near(c.x, c.y, 2500.0, 3.0, 12.0, 22.0)
	small.sort_custom(func(a, b): return a.c.distance_to(c) < b.c.distance_to(c))
	for b in small.slice(0, 80):
		var hc: Vector2 = b.c
		if _clear(Vector2(hc.x - 400.0, hc.y + 3.0), Vector2(1, 0), 380.0):
			await w.fly("%s house between CG and wingtip" % name, Vector2(hc.x - 400.0, hc.y + 3.0), 90.0, func(e, n): return b.top - 1.5, 80.0, 500.0, "%.0f m2 house h %.0f m, centre 3 m off the track" % [b.area, b.top - b.base], true, true)
			break


# ---- (c) taxi into buildings --------------------------------------------------------------

func _case_taxi() -> void:
	for icao in ["VAPO", "VABB", "VOCI"]:
		var a: Vector2 = apts[icao]
		await w.teleport_wait(a.x, a.y, 0.0, 90.0, 0.0, false)
		await w.frames(120)
		var bs := w.buildings_near(a.x, a.y, 1800.0, 3.0, 80.0)
		bs.sort_custom(func(x, y): return x.c.distance_to(a) < y.c.distance_to(a))
		var done := false
		for b in bs.slice(0, 120):
			var lo := INF
			for q in b.poly:
				lo = minf(lo, (q as Vector2).x)
			var start := Vector2(lo - 70.0, b.c.y)
			if not _clear(start, Vector2(1, 0), 66.0) or absf(w.terrain.height_at(start.x, start.y) - w.terrain.height_at(lo, start.y)) > 3.0:
				continue
			for kt in [5.0, 15.0]:
				await w.taxi("taxi %s into a building %.0f kt" % [icao, kt], start, 90.0, kt, 140.0, "bldg h %.0f m %.0f m2" % [b.top - b.base, b.area])
			done = true
			break
		if not done:
			w.row("taxi %s into a building" % icao, false, "-", "no clear approach found")


# ---- (d) airport structures --------------------------------------------------------------

func _case_airport() -> void:
	var lm = Paths.load_json("terminals/landmarks.json")
	for icao in ["VABB", "VAPO", "VOCI"]:
		var a: Vector2 = apts[icao]
		await w.teleport_wait(a.x, a.y, 0.0, 90.0, 0.0, false)
		await w.frames(240)
		await _model_coverage(icao)
		if lm and lm.has(icao) and not lm[icao].is_empty():
			var ring: Array = lm[icao][0]
			var c := Vector2.ZERO
			var lo := INF
			for q in ring:
				c += Vector2(q[0], q[1])
				lo = minf(lo, q[0])
			c /= ring.size()
			var start := Vector2(lo - 80.0, c.y)
			if _clear(start, Vector2(1, 0), 70.0):
				await w.taxi("terminal %s taxi 8 kt" % icao, start, 90.0, 8.0, 250.0, "footprint top %.0f, ground %.0f" % [w.bld.building_top_at(c.x, c.y), w.terrain.height_at(c.x, c.y)])
				await w.fly("terminal %s fly 80kt at 6 m" % icao, start - Vector2(400.0, 0.0), 90.0, func(e, n): return 6.0, 80.0, 700.0)
			else:
				w.row("terminal %s" % icao, false, "-", "no clear approach")
		await _ops_objects(icao)


## How much of the terminal model's surface (vertices above its paving) is solid in ObstacleRegistry.
func _model_coverage(icao: String) -> void:
	var terms: Terminals = f.get_node("Terminals")
	var s: Dictionary = terms._sites.get(icao, {})
	if s.is_empty() or s.node == null:
		w.row("terminal model coverage " + icao, false, "-", "model not loaded")
		return
	var t0 := Time.get_ticks_msec()
	while ObstacleRegistry.count("terminal:" + icao) == 0 and Time.get_ticks_msec() - t0 < 20000:
		await w.frames(10)
	var ground: float = s.origin.z
	var tot := 0
	var solid := 0
	var stack: Array = [s.node]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for ch in nd.get_children():
			stack.append(ch)
		if nd is MeshInstance3D and (nd as MeshInstance3D).mesh:
			var mi := nd as MeshInstance3D
			var faces := mi.mesh.get_faces()
			for i in range(0, faces.size(), 3):
				var wv := FloatingOrigin.to_world(mi.global_transform * faces[i])
				if wv.z < ground + 1.2:
					continue
				tot += 1
				var out := []
				ObstacleRegistry.near(wv.x, wv.y, 0.5, out)
				for o in out:
					if ObstacleShapes.segment_hits(Vector3(wv.x, wv.y, wv.z - 0.05), Vector3(wv.x, wv.y, wv.z + 0.05), o):
						solid += 1
						break
	w.row("terminal model coverage " + icao, false, "-", "%d model vertices above the paving: %.0f%% are solid in the collision raster (raster built in %.1f s)" % [tot, 100.0 * solid / maxf(tot, 1), (Time.get_ticks_msec() - t0) / 1000.0])


## Taxi into a jetway, a fuel truck, a GPU, ... of the airport's ground-ops dressing.
func _ops_objects(icao: String) -> void:
	var ops: AirportOps = f.get_node("AirportOps")
	var root: Node3D = ops._built.get(icao)
	if root == null:
		w.row("ops objects " + icao, false, "-", "AirportOps not built here")
		return
	var seen := {}
	for ch in root.get_children():
		var kind: String = ch.scene_file_path.get_file().get_basename() if ch is Node3D else ""
		if kind == "" or seen.get(kind, 0) >= 1:
			continue
		var p := FloatingOrigin.to_world(ch.global_position)
		var pc := Vector2(p.x, p.y)
		if kind == "jetway":
			pc += Vector2(ch.transform.basis.x.x, -ch.transform.basis.x.z) * 8.0 * ch.scale.x  # towards the cab
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var start: Vector2 = pc - d * 60.0
			if _clear(start, d, 50.0):
				seen[kind] = 1
				await w.taxi("taxi %s into a %s 6 kt" % [icao, kind], start, rad_to_deg(atan2(d.x, d.y)), 6.0, 90.0, "object at %.0f %.0f" % [pc.x, pc.y])
				break


# ---- (e) corridor ----------------------------------------------------------------------------

func _case_corridor() -> void:
	await _city("Kochi", apts["VOCI"] + Vector2(6000.0, -2000.0))


# ---- false positives: hull at every stand / pushback path / taxiway / runway --------------------

func _case_scan() -> void:
	var scan := ObstacleProbeScan.new(w, f.get_node("AirportOps"), f.get_node("Airports"))
	await scan.run(icao, not "--rules" in OS.get_cmdline_user_args())


# ---- cost of the check in a dense city and in open country ---------------------------------------------

func _case_perf() -> void:
	for q in [["Mumbai at 15 m AGL", Vector2(-60300.0, 25262.0), 15.0], ["Mumbai at 600 m", Vector2(-60300.0, 25262.0), 600.0],
			["forest at 8 m AGL", Vector2(12000, 12000), 8.0], ["VABB apron on the ground", apts["VABB"], 0.0]]:
		var c: Vector2 = q[1]
		await w.teleport_wait(c.x, c.y, 300.0, 90.0, 80.0)
		await w.frames(90)
		var fd := w.fn.fdm
		var oc := fd.obstacle_collision
		var calls := 0
		var with_cands := 0
		var t_all := 0
		var t_cand := 0
		for i in 400:
			var e := c.x + (i % 20) * 60.0
			var n := c.y + (i / 20) * 60.0
			fd.set_on_ground(n, e, 1.57)
			fd.pos_d = -(w.terrain.height_at(e, n) + q[2])
			var t0 := Time.get_ticks_usec()
			var cands: Array = fd.obstacles.call(e, n, 7.8, -fd.pos_d - 7.8, -fd.pos_d + 7.8)
			var t1 := Time.get_ticks_usec()
			for k in 20:
				oc.check(fd, true)
			var dt := (Time.get_ticks_usec() - t1) / 20.0
			t_all += int(dt + (t1 - t0))
			calls += 1
			if not cands.is_empty():
				with_cands += 1
				t_cand += int(dt + (t1 - t0))
		w.row("check cost " + q[0], false, "-", "%.0f us per step on average over 400 sites; %d sites had solids within 8 m and cost %.0f us there" % [t_all / float(calls), with_cands, t_cand / maxf(with_cands, 1)])


# ---- normal operations must not crash: takeoff, 3 degree approach and landing, taxi from a stand -------------

func _case_ops() -> void:
	var ab: AirportBuilder = f.get_node("Airports")
	for q in [["VABB", "27"], ["VABB", "09"], ["VAPO", "28"], ["VAPO", "10"], ["VOCI", "27"], ["VOCI", "09"], ["VAJJ", "08"], ["VANM", "26"], ["VOCC", "13"], ["VAAV", "09"]]:
		var st := ab.runway_start(q[0], q[1])
		if st.is_empty() or st.ident != q[1]:
			continue
		var hdg: float = st.heading_deg
		var dir := Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg)))
		var thr: Vector2 = st.pos - dir * 25.0
		var elev := w.terrain.height_at(thr.x, thr.y)
		# takeoff
		await w.teleport_wait(st.pos.x, st.pos.y, 0.0, hdg, 0.0, false)
		var fd := w.fn.fdm
		var pil := ObstacleProbePilot.new(fd, func(e: float, n: float) -> float: return w.terrain.height_at(e, n))
		pil.set_line(st.pos, hdg)
		fd.prop.rpm = 800.0
		var lift := -1.0
		for i in 240 * 70:
			pil.takeoff()
			if fd.damage.crashed:
				break
			if lift < 0.0 and fd.agl > 3.0 and not fd.gear.wow:
				lift = Vector2(fd.pos_e, fd.pos_n).distance_to(st.pos)
		w.row("takeoff %s %s" % q, fd.damage.crashed, fd.damage.crash_reason, "airborne after %.0f m, agl %.0f m, %.0f kt at 70 s" % [lift, fd.agl, fd.cas / 0.514444])
		# 3 degree final from 3 nm, landing and roll-out
		var start: Vector2 = thr - dir * 3.0 * 1852.0
		var alt0 := elev + (3.0 * 1852.0 + 300.0) * tan(deg_to_rad(3.0))
		await w.teleport_wait(start.x, start.y, alt0, hdg, 65.0)
		fd = w.fn.fdm
		var pl := ObstacleProbePilot.new(fd, func(e: float, n: float) -> float: return w.terrain.height_at(e, n))
		pl.set_line(thr, hdg)
		var stopped := false
		for i in 240 * 260:
			if pl.land(thr, elev) or fd.damage.crashed:
				stopped = true
				break
		var past := (Vector2(fd.pos_e, fd.pos_n) - thr).dot(dir)
		w.row("landing %s %s (3 nm final)" % q, fd.damage.crashed, fd.damage.crash_reason, "stopped %s, %.0f m past the threshold, %.1f m off the centreline" % [stopped, past, absf((Vector2(fd.pos_e, fd.pos_n) - thr).cross(dir))])


# ---- (f) fast approach --------------------------------------------------------------------------

func _case_fast() -> void:
	var c := Vector2(-60300.0, 25262.0)
	await w.teleport_wait(c.x, c.y, 300.0, 90.0, 80.0)
	await w.frames(60)
	var big := w.buildings_near(c.x, c.y, 2500.0, 12.0, 400.0)
	big.sort_custom(func(a, b): return a.top > b.top)
	for b in big.slice(0, 40):
		if _clear(b.c - Vector2(300.0, 0.0), Vector2(1, 0), 280.0):
			for kias in [120.0, 150.0]:
				await w.fly("fast nose-on %.0f kt (tunnelling)" % kias, b.c - Vector2(700.0, 0.0), 90.0, func(e, n): return b.top - 4.0, kias, 900.0, "top %.0f" % b.top, true, true)
			return
