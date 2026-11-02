class_name GroundChoice
extends RefCounted
## Which stands and runways suit the aircraft. The stand record (tools/airport_stands.py) has no size
## class, so it is derived here from the fields it has: a jetbridge gate, a GA tie-down (ref "GA..." or a
## synthesised stand) or any other remote bay. The aircraft says what it wants in aircraft.json
## ground.stand_class: "any" (default, no preference: the C172's legacy behaviour), "ga" (not a jetbridge
## gate) or "gate" (not a GA tie-down; jetbridge gates first). ground.min_runway_m rules out short runways.

const TOO_SHORT := -1000.0  # score penalty: a too-short runway is taken only when there is no other


static func stand_class(st: Dictionary) -> String:
	if st.get("jetbridge", false):
		return "gate"
	if str(st.get("ref", "")).begins_with("GA") or st.get("src", "") == "synth":
		return "ga"
	return "remote"


## Can an aircraft of class `cls` use the stand? "any" takes all.
static func suits(st: Dictionary, cls: String) -> bool:
	var c := stand_class(st)
	if cls == "gate":
		return c != "ga"
	if cls == "ga":
		return c != "gate"
	return true


## Lower is better: the order the start screen offers the stands for `cls`. "any" keeps the data order.
static func rank(st: Dictionary, cls: String) -> int:
	var c := stand_class(st)
	if cls == "gate":
		return {"gate": 0, "remote": 1, "ga": 2}[c]
	if cls == "ga":
		return {"ga": 0, "remote": 1, "gate": 2}[c]
	return 0


## The stands to offer for `cls`, best first (stable); only the suitable ones unless none is.
static func offered(stands: Array, cls: String) -> Array:
	if cls != "gate" and cls != "ga":
		return stands
	var ok := stands.filter(func(s): return suits(s, cls))
	var keyed := []
	for i in (ok if not ok.is_empty() else stands).size():
		var st: Dictionary = (ok if not ok.is_empty() else stands)[i]
		keyed.append([rank(st, cls), i, st])
	keyed.sort_custom(func(x, y): return x[1] < y[1] if x[0] == y[0] else x[0] < y[0])
	return keyed.map(func(k): return k[2])


## The default stand ("" = no ref asked for): "any" = the first jetbridge gate else the first stand (legacy).
static func default_stand(stands: Array, cls: String) -> Dictionary:
	if stands.is_empty():
		return {}
	if cls == "gate" or cls == "ga":
		return offered(stands, cls)[0]
	for s in stands:
		if s.get("jetbridge", false):
			return s
	return stands[0]


## Extra distance (m) that makes a stand less attractive for "taxi to the apron" after landing.
## Legacy ("any", "ga"): a jetbridge gate is avoided (ramp stands preferred). Airliners: GA tie-downs
## are out, remote bays are second to gates.
static func taxi_penalty(st: Dictionary, cls: String) -> float:
	if cls == "gate":
		return {"gate": 0.0, "remote": 150.0, "ga": 1000.0}[stand_class(st)]
	return 400.0 if st.get("jetbridge", false) else 0.0


## Runway end score (headwind + length/1000 as before, headwind in any one unit) with the too-short
## penalty for ground.min_runway_m (0 = none).
static func runway_score(headwind: float, length_m: float, min_runway_m := -1.0) -> float:
	var need := min_runway_m if min_runway_m >= 0.0 else float(GroundParams.ground().min_runway_m)
	return headwind + length_m / 1000.0 + (TOO_SHORT if length_m < need else 0.0)
