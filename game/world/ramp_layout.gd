class_name RampLayout
extends RefCounted
## Where the ramp crew parks around an aircraft on a stand, from its RampPoints: pushback tug ahead of the nose wheel, GPU
## at the ground-power receptacle, fuel truck (remote stand) or hydrant dispenser (contact gate) at the refuel coupling,
## a baggage train at each cargo door (trailing away from the wing), apron bus at the first passenger door of a remote stand.
## Each vehicle starts at its service point and slides (along, then outward) until clear of the airframe keep-out (fuselage,
## wing and tail unless it fits under, engines with intake / exhaust zones, taxi-in path), of vehicles already placed and of
## whatever `blocked` reports (jetways, terminals, other dressing). Pure: no nodes. Stand frame [forward, right] about the CG.

const AIRFRAME_GAP := 0.8  # m between a vehicle and the airframe / a danger zone
const VEHICLE_GAP := 0.8  # m between two vehicles
const UNDER_GAP := 0.4  # m between a vehicle roof and a wing it parks under
const STEP := 0.5
const SLIDE_M := 14.0  # how far a vehicle may slide from its service point
const OUT_M := 4.0  # and outward
const BASE_COST := 4.0  # m: a further base is used only when it is this much nearer its point

static var _boxes := {}  # kind -> AABB of its mesh (scale 1)


## Placements for an aircraft on stand st: [{kind, service, f, r, a (heading relative to the aircraft, rad),
## pos (world east, north), heading (compass rad), scale, top (m), poly (world footprint), point ([f, r] it serves)}].
## blocked(world_poly: PackedVector2Array, top: float) -> bool: something else stands there (null = nothing).
static func plan(def: AircraftDef, st: Dictionary, blocked: Variant = null) -> Array:
	var rp := RampPoints.of(def)
	var parts := RampPoints.keep_out(rp)
	var frame := _frame(st, def)
	var out := []
	for it in _items(rp, bool(st.get("jetbridge", false))):
		var got := _fit(it, parts, out, frame, blocked)
		out.append_array(got)
	return out


## The service items: {service, kinds (front to back), scale, bases: [[f, r, a, (point it serves there)]], axis
## (Vector2 slide in [f, r]), both (slide both ways), point}; outward = away from the centre line of the base.
static func _items(rp: Dictionary, gate: bool) -> Array:
	var fus := float(rp.fuselage_half_m)
	var out := []
	if rp.tug:
		var s := float(rp.tug_scale)
		var l := size("pushback_tug", s)
		var ng := float(rp.nose_gear_f)
		out.append({"service": "tug", "kinds": ["pushback_tug"], "scale": s, "point": [ng, 0.0], "both": false,
			"axis": Vector2(1, 0), "bases": [[float(rp.nose_f) + 1.5 + l.y * 0.5, 0.0, PI], [ng, fus + 2.5 + l.x * 0.5, 0.0]]})
	if rp.gpu != null:
		var p: Array = rp.gpu
		var sd := _side(p)
		var l := size("gpu")
		out.append({"service": "gpu", "kinds": ["gpu"], "scale": 1.0, "point": p, "both": true, "axis": Vector2(1, 0),
			"bases": [[float(p[0]) + 0.3, sd * (maxf(absf(float(p[1])), fus) + 0.9 + l.x * 0.5), 0.0]]})
	if rp.refuel != null:
		var p: Array = rp.refuel
		var k := "hydrant_dispenser" if gate and rp.big else "fuel_truck"
		out.append({"service": "fuel", "kinds": [k], "scale": 1.0, "point": p, "both": false, "axis": Vector2(1, 0),
			"bases": [[float(p[0]), float(p[1]), 0.0], [float(p[0]), -float(p[1]), 0.0, [p[0], -float(p[1])]]]})  # or the other wing's
	var wing_f := _centre_f(rp.wing.outline)
	for p in rp.cargo:
		var sd := _side(p)
		var dir := 1.0 if float(p[0]) > wing_f else -1.0
		var kinds := ["baggage_tug", "baggage_cart", "baggage_cart"]
		var l := _unit(kinds, 1.0)
		var w := size("baggage_cart").x
		out.append({"service": "cargo", "kinds": kinds, "scale": 1.0, "point": p, "both": false, "axis": Vector2(dir, 0),
			"bases": [[float(p[0]) + dir * (l * 0.5 - 2.0), sd * (fus + 1.5 + w * 0.5), 0.0 if dir > 0.0 else PI]]})
	if not gate and rp.big and not rp.doors.is_empty():
		var p: Array = rp.doors[0]
		var sd := _side(p)
		var l := size("apron_bus")
		out.append({"service": "bus", "kinds": ["apron_bus"], "scale": 1.0, "point": p, "both": true, "axis": Vector2(1, 0),
			"bases": [[float(p[0]), sd * (fus + 3.0 + l.x * 0.5), 0.0]]})
	return out


## The spots nearest the service point first (gap to the point, plus a little for the slide, each further base BASE_COST
## more: the other wing, beside the nose); the first clear spot wins ([] = no room).
static func _fit(it: Dictionary, parts: Array, placed: Array, frame: Array, blocked: Variant) -> Array:
	var cands := []
	for bi in it.bases.size():
		var b: Array = it.bases[bi]
		var pt: Array = b[3] if b.size() > 3 else it.point
		var sd := signf(float(b[1])) if absf(float(b[1])) > 0.01 else 1.0
		var d := -SLIDE_M if it.both else 0.0
		while d <= SLIDE_M + 1e-3:
			var o := 0.0
			while o <= OUT_M + 1e-3:
				var got := _members(it, Vector2(b[0], b[1]) + it.axis * d + Vector2(0, sd) * o, float(b[2]), frame, pt)
				cands.append([gap(got, Vector2(pt[0], pt[1])) + 0.2 * (absf(d) + o) + BASE_COST * bi, got])
				o += STEP
			d += STEP
	cands.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])
	for c in cands:
		if _clear(c[1], parts, placed, blocked):
			return c[1]
	return []


## Distance (stand frame) from a service point to the nearest footprint of an item (0 inside one).
static func gap(got: Array, pt: Vector2) -> float:
	var best := INF
	for v in got:
		if Geometry2D.is_point_in_polygon(pt, v.local):
			return 0.0
		for i in 4:
			best = minf(best, Geometry2D.get_closest_point_to_segment(pt, v.local[i], v.local[(i + 1) % 4]).distance_to(pt))
	return best


## The vehicles of an item centred at c (stand frame) facing a: each member's footprint and world pose.
static func _members(it: Dictionary, c: Vector2, a: float, frame: Array, point: Array) -> Array:
	var s := float(it.scale)
	var vf := Vector2(cos(a), sin(a))
	var total := _unit(it.kinds, s)
	var x := total * 0.5  # the front of the unit, along vf
	var out := []
	for kind in it.kinds:
		var box := aabb(kind)
		var l := box.size.z * s
		var mc := c + vf * (x - l * 0.5)  # centre of this member's box
		x -= l + 0.6
		var origin := mc - vf * (-(box.position.z + box.size.z * 0.5) * s) - Vector2(-vf.y, vf.x) * ((box.position.x + box.size.x * 0.5) * s)
		var poly := _poly(mc, vf, l, box.size.x * s)
		out.append({"kind": kind, "service": it.service, "f": origin.x, "r": origin.y, "a": a, "scale": s, "top": box.end.y * s,
			"local": poly, "point": point, "pos": _world(frame, origin), "heading": float(frame[1]) + a, "poly": _world_poly(frame, poly)})
	return out


static func _clear(got: Array, parts: Array, placed: Array, blocked: Variant) -> bool:
	for v in got:
		var grown := Geometry2D.offset_polygon(v.local, AIRFRAME_GAP)
		var r_in := INF
		for p in v.local:
			r_in = minf(r_in, absf(p.y))
		for part in parts:
			if part.low is Array or float(part.low) > 0.0:
				if v.top + UNDER_GAP < RampPoints.low_at(part, r_in):
					continue  # it fits under (a high wing, a tailplane)
			if not grown.is_empty() and not Geometry2D.intersect_polygons(grown[0], part.poly).is_empty():
				return false
		var spaced := Geometry2D.offset_polygon(v.local, VEHICLE_GAP)
		for q in placed:
			if not Geometry2D.intersect_polygons(spaced[0], q.local).is_empty():
				return false
		if blocked != null and (blocked as Callable).call(v.poly, float(v.top)):
			return false
	return true


## [cg (world), heading] of the aircraft parked on the stand.
static func _frame(st: Dictionary, def: AircraftDef) -> Array:
	return [GroundParams.cg_at_stand(st, def), deg_to_rad(float(st.heading_deg))]


## Stand frame [f, r] -> world (east, north).
static func _world(frame: Array, p: Vector2) -> Vector2:
	var hd: float = frame[1]
	return (frame[0] as Vector2) + Vector2(sin(hd), cos(hd)) * p.x + Vector2(cos(hd), -sin(hd)) * p.y


static func _world_poly(frame: Array, poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(_world(frame, p))
	return out


static func to_world(st: Dictionary, p: Vector2, def: AircraftDef = null) -> Vector2:
	return _world(_frame(st, def), p)


static func _poly(c: Vector2, vf: Vector2, l: float, w: float) -> PackedVector2Array:
	var vr := Vector2(-vf.y, vf.x)
	return PackedVector2Array([c + vf * l * 0.5 + vr * w * 0.5, c + vf * l * 0.5 - vr * w * 0.5, c - vf * l * 0.5 - vr * w * 0.5, c - vf * l * 0.5 + vr * w * 0.5])


static func _unit(kinds: Array, s: float) -> float:
	var l := 0.0
	for k in kinds:
		l += aabb(k).size.z * s
	return l + 0.6 * (kinds.size() - 1)  # tow bars


static func _side(p: Array) -> float:
	return -1.0 if float(p[1]) < 0.0 else 1.0


static func _centre_f(outline: Array) -> float:
	var s := 0.0
	for p in outline:
		s += float(p[0])
	return s / maxf(outline.size(), 1)


## Vehicle mesh bounds (model frame: faces -Z, x right, origin on the ground).
static func aabb(kind: String) -> AABB:
	if not _boxes.has(kind):
		_boxes[kind] = GroundVehicles.mesh(kind).get_aabb()
	return _boxes[kind]


## [width, length] of a kind at a scale.
static func size(kind: String, s := 1.0) -> Vector2:
	var b := aabb(kind)
	return Vector2(b.size.x, b.size.z) * s
