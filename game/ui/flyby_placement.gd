class_name FlybyPlacement
extends RefCounted
## Where the fly-by camera (CameraRig mode 8) stands, how far it zooms and when it re-places. Pure functions
## of the aircraft's size and velocity, so a 140 kt airliner and a 100 kt C172 both pass the camera after
## about the same few seconds, each at a distance that suits its size. ENU metres (east, north, up AMSL).
##
## Size = max(wingspan (config.json metrics.wingspan_m), ground footprint length (aircraft.json ground ahead_m +
## behind_m)). aircraft.json cameras.flyby (optional dictionary, defaults in DEFAULTS) tunes it:
##   lead_s       seconds until the aircraft is abeam the camera (ahead = ground speed x lead_s, clamped by size)
##   side_sizes   lateral offset from the track, in aircraft sizes
##   up_sizes     height above the pass point, in aircraft sizes
##   frame        fraction of the frame height the aircraft's size should cover (the zoom), fov_min / fov_max deg
##   ahead_sizes  [min, max] distance ahead, in sizes; replace_k: re-place once the aircraft is this x ahead past it
## The camera never stands in terrain or an obstacle (env.height / env.obstacle_top + MARGIN_M), avoids
## a candidate whose view of the pass point is blocked by terrain and prefers one outside cloud (env.cloud).

const DEFAULTS := {"lead_s": 5.0, "side_sizes": 2.3, "up_sizes": 0.45, "frame": 0.42, "fov_min": 10.0, "fov_max": 55.0,
	"ahead_sizes": [3.0, 40.0], "replace_k": 0.9}
const MARGIN_M := 3.0  # camera at least this far above the ground / an obstacle top (plus 5 % of the size)
const SLOW_MPS := 3.0  # below this the aircraft counts as standing: the camera stands off its nose
const CLOUD_MAX := 0.05  # a candidate with more cloud density than this at the camera / on the sight line is avoided
const LOS_SAMPLES := 8


## The fly-by parameters of an aircraft: DEFAULTS merged with aircraft.json cameras.flyby, plus "size_m".
static func params(def: AircraftDef) -> Dictionary:
	var p := DEFAULTS.duplicate(true)
	var own = def.section("cameras").get("flyby", {}) if def else {}
	if own is Dictionary:
		p.merge(own, true)
	var span := 10.9
	var length := 10.7
	if def:
		span = float(def.config().get("metrics", {}).get("wingspan_m", span))
		var g := GroundParams.ground(def)
		length = float(g.get("ahead_m", 3.3)) + float(g.get("behind_m", 7.4))
	p.size_m = maxf(span, length)
	return p


## Camera position for an aircraft at w moving with v (ENU m/s); fwd = horizontal unit direction to use when it
## stands still (its nose). env: optional {height: Callable(e, n) -> ground m, obstacle_top: Callable(e, n) -> top m
## or -INF, cloud: Callable(Vector3) -> density 0..1}. Returns {pos, pass_pt (the point abeam the camera), ahead_m, score}.
static func place(w: Vector3, v: Vector3, fwd: Vector2, p: Dictionary, env := {}) -> Dictionary:
	var size: float = p.size_m
	var hs := Vector2(v.x, v.y).length()
	var dir := Vector2(v.x, v.y) / hs if hs > SLOW_MPS else (fwd.normalized() if fwd.length() > 0.01 else Vector2(0, 1))
	var lim: Array = p.ahead_sizes
	var ahead := clampf(hs * float(p.lead_s), float(lim[0]) * size, float(lim[1]) * size)
	var right := Vector3(dir.y, -dir.x, 0.0)
	var best := {}
	var rank := 0
	for along_k in [1.0, 0.75, 1.35]:
		var a: float = ahead * along_k
		# pass point: where the aircraft will be (its climb / descent included) when it has flown a metres
		var pass_pt := w + (v / hs * a if hs > SLOW_MPS else Vector3(dir.x, dir.y, 0.0) * a)
		for side in [1.0, -1.0]:
			for up_k in [1.0, -1.0, 2.5]:
				var pos: Vector3 = pass_pt + right * side * float(p.side_sizes) * size + Vector3.UP * up_k * float(p.up_sizes) * size
				var c := _score(pos, pass_pt, w, size, env)
				c.score += rank * 0.5  # preference order breaks ties
				rank += 1
				if best.is_empty() or c.score < best.score:
					c.pass_pt = pass_pt
					c.ahead_m = a
					best = c
	return best


## Penalty of one candidate (lower = better), with the camera lifted clear of the ground / obstacles.
static func _score(pos: Vector3, pass_pt: Vector3, w: Vector3, size: float, env: Dictionary) -> Dictionary:
	var score := 0.0
	var floor_m := floor_at(pos.x, pos.y, size, env)
	if pos.z < floor_m:
		score += (floor_m - pos.z) / size * 4.0  # lifting it far changes the picture: prefer one that fits
		pos.z = floor_m
	var hc: Callable = env.get("height", Callable())
	if hc.is_valid():  # terrain between the camera and the pass_pt point / the aircraft now hides it
		for target in [pass_pt, w]:
			for i in range(1, LOS_SAMPLES):
				var q: Vector3 = pos.lerp(target, float(i) / LOS_SAMPLES)
				if float(hc.call(q.x, q.y)) > q.z - 0.5:
					score += 50.0
					break
	var cc: Callable = env.get("cloud", Callable())
	if cc.is_valid():
		var dens := maxf(float(cc.call(pos)), float(cc.call(pos.lerp(pass_pt, 0.5))))
		if dens > CLOUD_MAX:
			score += 20.0 + 20.0 * dens
	return {"pos": pos, "score": score}


## Lowest camera height at (e, n): ground or obstacle top plus MARGIN_M (and 5 % of the size); -INF without env.
static func floor_at(e: float, n: float, size: float, env: Dictionary) -> float:
	var top := -INF
	var hc: Callable = env.get("height", Callable())
	if hc.is_valid():
		top = float(hc.call(e, n))
	var oc: Callable = env.get("obstacle_top", Callable())
	if oc.is_valid():
		top = maxf(top, float(oc.call(e, n)))
	return top + MARGIN_M + 0.05 * size if top > -INF else -INF


## Vertical field of view (deg) that makes the aircraft's size cover p.frame of the frame height at dist m.
static func fov_deg(dist: float, p: Dictionary) -> float:
	var want := rad_to_deg(2.0 * atan(float(p.size_m) / (2.0 * float(p.frame) * maxf(dist, 0.1))))
	return clampf(want, float(p.fov_min), float(p.fov_max))


## True when the camera at cam should be re-placed: the aircraft (w, v) is past it by replace_k x the distance it
## was placed ahead, or it is far away in any direction (it turned and will not pass).
static func needs_replace(cam: Vector3, w: Vector3, v: Vector3, ahead_m: float, p: Dictionary) -> bool:
	var size: float = p.size_m
	var rel := w - cam
	var hs := Vector2(v.x, v.y).length()
	if hs > SLOW_MPS:
		var along := Vector2(rel.x, rel.y).dot(Vector2(v.x, v.y) / hs)
		if along > maxf(ahead_m * float(p.replace_k), 2.0 * size):
			return true
	return rel.length() > 2.2 * ahead_m + float(p.side_sizes) * size + 4.0 * size


## The env Callables for place() in a flight: terrain height, obstacles (registry, OSM buildings, trees) and cloud.
static func env_for(fdm_node: FdmNode) -> Dictionary:
	var env := {}
	var tq: TerrainQuadtree = fdm_node._terrain if fdm_node else null
	if tq:
		env.height = func(e: float, n: float) -> float: return tq.height_at(e, n)
	var obs: Callable = fdm_node.fdm.obstacles if fdm_node and fdm_node.fdm else Callable()
	if obs.is_valid():
		env.obstacle_top = func(e: float, n: float) -> float:
			var top := -INF
			for rec in obs.call(e, n, 4.0, -INF, INF):
				var lo: Vector2 = rec.lo
				var hi: Vector2 = rec.hi
				if e >= lo.x - 4.0 and e <= hi.x + 4.0 and n >= lo.y - 4.0 and n <= hi.y + 4.0:
					top = maxf(top, float(rec.get("top", -INF)))
			return top
	var c := CloudPhysics.conditions()
	if float(c.cover) > 0.0:
		env.cloud = func(q: Vector3) -> float: return CloudField.density(q, c.base_m, c.cover, c.drift)
	return env
