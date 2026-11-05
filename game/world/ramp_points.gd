class_name RampPoints
extends RefCounted
## Where a ramp crew services an aircraft and what it keeps clear of, from aircraft.json "ramp"; a missing key is derived
## from the aircraft's size (config.json, "ground"). Frame: about the CG on the ground, [forward, right] metres (the stand
## frame of GroundParams.cg_at_stand), heights in metres above the ground.
## ramp: fuselage_half_m   half width of the fuselage
##       wing      {outline: [[f, r], ...] the right wing (mirrored), low_m: [root, tip] underside height}
##       tailplane {outline, low_m} the same for the horizontal tail
##       engines   [{at: [f, r], length_m, radius_m, intake_m, exhaust_m}]: each listed (no mirroring); intake_m /
##                 exhaust_m: danger zone ahead of / behind it
##       gpu       [f, r] ground-power receptacle, null = none;  refuel: [f, r] refuel coupling or filler cap, null = none
##       cargo     [[f, r], ...] cargo / baggage doors (a baggage train each)
##       doors     [[f, r], ...] passenger doors (the first gets the apron bus at a remote stand)
##       tug       false = no pushback tug ahead of the nose (default true)

const MARGIN := 1.2  # the "ground" footprint (ahead_m, behind_m) is the airframe plus this
const BIG_M := 20.0  # longer than this: an airliner (ground power, cargo holds, doors by default)


## Everything a RampLayout needs: the section over the derived defaults.
static func of(def: AircraftDef = null) -> Dictionary:
	if def == null:
		def = AircraftDef.current()
	var g := GroundParams.ground(def)
	var r: Dictionary = def.section("ramp")
	var nose := float(g.ahead_m) - MARGIN
	var tail := -(float(g.behind_m) - MARGIN)
	var length := nose - tail
	var big := length > BIG_M
	var d := _derived(def, nose, tail, big)
	var out := {"nose_f": nose, "tail_f": tail, "length": length, "big": big, "height_m": float(g.height_m),
		"nose_gear_f": float(g.nose_gear_m), "tug_scale": float(g.tug_scale)}
	for k in d:
		out[k] = r.get(k, d[k])
	out.tug = bool(r.get("tug", true))
	return out


## Defaults from the flight-model config: fuselage width from the length, a straight wing at the aero
## reference point (solid to the ground), the engines at their thrust points.
static func _derived(def: AircraftDef, nose: float, tail: float, big: bool) -> Dictionary:
	var cfg := def.config()
	var m: Dictionary = cfg.get("metrics", {})
	var cg_x := float(cfg.get("mass", {}).get("empty_cg_m", [0.0, 0.0, 0.0])[0])
	var ground_z := INF
	for gr in cfg.get("gear", []):
		ground_z = minf(ground_z, float(gr.pos_m[2]))
	if ground_z == INF:
		ground_z = 0.0
	var length := nose - tail
	var half_span := float(m.get("wingspan_m", length)) * 0.5
	var chord := float(m.get("chord_m", 0.12 * length))
	var ref: Array = m.get("aero_ref_pt_m", [cg_x, 0.0, ground_z])
	var wf := cg_x - float(ref[0])  # structural x is aft: forward of the CG = cg_x - x
	var fus := clampf(0.055 * length, 0.5, 3.5)
	var out := {"fuselage_half_m": fus,
		"wing": {"outline": [[wf + 0.6 * chord, fus], [wf + 0.6 * chord, half_span], [wf - 0.6 * chord, half_span], [wf - 0.6 * chord, fus]], "low_m": [0.0, 0.0]},
		"tailplane": {"outline": [[tail + 0.12 * length, fus * 0.3], [tail + 0.02 * length, 0.2 * half_span], [tail, 0.2 * half_span], [tail, fus * 0.3]], "low_m": [0.0, 0.0]},
		"engines": [], "gpu": null, "refuel": null, "cargo": [], "doors": []}
	for e in cfg.get("engines", []):
		var p: Array = e.get("pos_m", [cg_x, 0.0, 0.0])
		var rad := clampf(0.035 * half_span * 2.0, 0.6, 2.0)
		out.engines.append({"at": [cg_x - float(p[0]), float(p[1])], "length_m": rad * 3.5, "radius_m": rad, "intake_m": rad * 2.5, "exhaust_m": rad * 5.0})
	if cfg.has("propeller"):  # a single piston engine: the propeller disc at the nose
		out.engines.append({"at": [nose - 0.3, 0.0], "length_m": 0.6, "radius_m": 1.0, "intake_m": 1.5, "exhaust_m": 0.0})
	if big:
		var ng := float(GroundParams.ground(def).nose_gear_m)
		out.gpu = [ng + 0.4 * (nose - ng), fus * 0.6]
		out.refuel = [wf, 0.45 * half_span]
		out.cargo = [[(ng + wf + 0.6 * chord) * 0.5, fus], [(wf - 0.6 * chord + tail * 0.6) * 0.5, fus]]
		out.doors = [[float(GroundParams.ground(def).cg_to_door_m), -fus]]
	return out


## The parts of the airframe as keep-out shapes in the stand frame: [{poly: PackedVector2Array of [f, r],
## low: height of its underside (0 = solid to the ground), part}]. Wing and tailplane both sides.
static func keep_out(rp: Dictionary) -> Array:
	var fus := float(rp.fuselage_half_m)
	var out := [{"part": "fuselage", "low": 0.0, "poly": _rect(rp.nose_f, rp.tail_f, -fus, fus)}]
	for k in ["wing", "tailplane"]:
		var w: Dictionary = rp[k]
		for side in [1.0, -1.0]:
			var poly := PackedVector2Array()
			for p in w.outline:
				poly.append(Vector2(float(p[0]), float(p[1]) * side))
			out.append({"part": ("right " if side > 0.0 else "left ") + k, "poly": poly, "low": w.low_m, "span": _span(w.outline)})
	for e in rp.engines:
		var f := float(e.at[0])
		var r := float(e.at[1])
		var half := float(e.length_m) * 0.5
		var rad := float(e.radius_m)
		out.append({"part": "engine", "low": 0.0, "poly": _rect(f + half, f - half, r - rad, r + rad)})
		out.append({"part": "engine intake zone", "low": 0.0, "poly": _rect(f + half + float(e.intake_m), f + half, r - rad - 0.5, r + rad + 0.5)})
		if float(e.exhaust_m) > 0.0:
			out.append({"part": "engine exhaust zone", "low": 0.0, "poly": _rect(f - half, f - half - float(e.exhaust_m), r - rad, r + rad)})
	# the taxi-in path: the lead-in line behind the tail stays clear
	out.append({"part": "taxi-in path", "low": 0.0, "poly": _rect(rp.tail_f, rp.tail_f - maxf(25.0, rp.length), -fus - 1.0, fus + 1.0)})
	return out


## Underside height of a keep-out part over the lateral distance |r| (wing dihedral: low at the root, higher at the tip).
static func low_at(part: Dictionary, r: float) -> float:
	var low = part.low
	if low is Array:
		var s: Vector2 = part.span
		var t := clampf((absf(r) - s.x) / maxf(s.y - s.x, 0.01), 0.0, 1.0)
		return lerpf(float(low[0]), float(low[1]), t)
	return float(low)


static func _span(outline: Array) -> Vector2:
	var lo := INF
	var hi := 0.0
	for p in outline:
		lo = minf(lo, absf(float(p[1])))
		hi = maxf(hi, absf(float(p[1])))
	return Vector2(lo, hi)


static func _rect(f0: float, f1: float, r0: float, r1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(f0, r0), Vector2(f0, r1), Vector2(f1, r1), Vector2(f1, r0)])
