class_name SetupChecks
extends RefCounted
## Readiness of a free-flight setup (what the start screen looks at before FLY). Pure logic over a
## Session.setup-shaped Dictionary, no nodes. checks() returns the problems found:
##   [{step: "aircraft" | "airport" | "weather", level: "bad" | "warn", id, text}]
## An empty list is a ready setup. Levels:
##   bad   over maximum takeoff weight, CG outside the envelope, runway shorter than ground.min_runway_m (runway
##         starts only), tailwind above TAILWIND_KT, crosswind above limits.max_crosswind_kt (the last two on a
##         runway start AND an air start: the air start lines up with the same runway; not on a stand start).
##         These make Fly ask "Fly anyway?".
##   warn  visibility under LOW_VIS_M. Never asks.
## The values come from the aircraft (AircraftDef: mtow_kg, cg_envelope via WeightBalance, ground.min_runway_m,
## limits.max_crosswind_kt) and the runway data (runways.json, the same file the airport page reads). The runway
## the flight uses is looked up as world/airport_builder.gd runway_start does: the ident, else the longest runway.
## Gusts are not counted. Mirrors W.checks of the chosen design (docs/ui-rework/widgets.js).

const TAILWIND_KT := 5.0  # a tailwind above this is "bad" (exactly 5 is not)
const LOW_VIS_M := 1600.0
const DEFAULT_MAX_CROSSWIND_KT := 15.0

static var _runways := []  # runways.json "runways", loaded on first use


## All problems of the setup. `rwy` ({ident, length_m, heading_deg}) overrides the runway lookup (tests, callers
## that already know it); {} = look it up from the setup's airport and runway.
static func checks(setup: Dictionary, rwy := {}) -> Array:
	var out := []
	var ac := AircraftDef.load_def(str(setup.get("aircraft", AircraftDef.DEFAULT_ID)))
	if ac == null:
		return out
	_weight(ac, setup, out)
	var start := str(setup.get("start", "runway"))
	if start != "stand":
		if rwy.is_empty():
			rwy = runway_of(setup)
		if not rwy.is_empty():
			if start == "runway":
				_length(ac, rwy, out)
			_wind(ac, setup, rwy, out)
	if float(setup.get("visibility_m", 40000.0)) < LOW_VIS_M:
		out.append(_item("weather", "warn", "low_visibility", "Visibility under %s km" % ("%.1f" % (LOW_VIS_M / 1000.0))))
	return out


## "bad" when any check is bad, else "warn" when any is, else "ok".
static func worst(list: Array) -> String:
	var r := "ok"
	for c in list:
		if c.level == "bad":
			return "bad"
		r = "warn"
	return r


## The texts of the "bad" checks (what the Fly anyway dialog lists).
static func reasons(list: Array) -> Array[String]:
	var out: Array[String] = []
	for c in list:
		if c.level == "bad":
			out.append(c.text)
	return out


## The worst level of one step ("aircraft" | "airport" | "weather"), for the rail and chips.
static func step_level(list: Array, step: String) -> String:
	return worst(list.filter(func(c): return c.step == step))


## The runway of the setup as {ident, length_m, heading_deg}; {} when the data or the airport is missing.
static func runway_of(setup: Dictionary) -> Dictionary:
	var rws := _load_runways().filter(func(r): return r.airport == str(setup.get("airport", "")))
	rws.sort_custom(func(a, b): return a.length > b.length)  # no ident (or an unknown one): the longest
	var want := str(setup.get("runway", ""))
	for pass_no in 2:
		for r in rws:
			for e in r.ends:
				if want == "" or e.ident == want:
					return {"ident": str(e.ident), "length_m": float(r.length), "heading_deg": float(e.heading_true)}
		want = ""
	return {}


## Head wind (negative = tail) and cross wind (positive = from the right), knots, on a runway heading.
static func wind_components(wind_dir_deg: float, wind_kt: float, runway_heading_deg: float) -> Vector2:
	var rel := deg_to_rad(wind_dir_deg - runway_heading_deg)
	return Vector2(wind_kt * cos(rel), wind_kt * sin(rel))


static func max_crosswind_kt(ac: AircraftDef) -> float:
	return float(ac.section("limits").get("max_crosswind_kt", DEFAULT_MAX_CROSSWIND_KT))


static func _item(step: String, level: String, id: String, text: String) -> Dictionary:
	return {"step": step, "level": level, "id": id, "text": text}


static func _weight(ac: AircraftDef, setup: Dictionary, out: Array) -> void:
	var j := ac.data
	if not j.has("mtow_kg"):
		return
	var cfg := WeightBalance.load_config(j)
	var over := WeightBalance.takeoff_kg(j, setup, cfg) - float(j.mtow_kg)
	if over > 0.0:
		out.append(_item("aircraft", "bad", "over_weight", "Over maximum takeoff weight by %d kg" % maxi(ceili(over - 1e-6), 1)))
	var wb := WeightBalance.compute(j, setup, cfg)
	if not wb.is_empty() and not wb.ok:
		out.append(_item("aircraft", "bad", "cg_out", "CG outside the envelope"))


static func _length(ac: AircraftDef, rwy: Dictionary, out: Array) -> void:
	var need := float(GroundParams.ground(ac).min_runway_m)
	if need > 0.0 and float(rwy.length_m) < need:
		out.append(_item("airport", "bad", "runway_short", "Runway %s is %d m, too short (needs %d m)" % [rwy.ident, int(rwy.length_m), ceili(need)]))


static func _wind(ac: AircraftDef, setup: Dictionary, rwy: Dictionary, out: Array) -> void:
	var w := wind_components(float(setup.get("wind_dir_deg", 0.0)), float(setup.get("wind_kt", 0.0)), float(rwy.heading_deg))
	var tail := -w.x
	if tail > TAILWIND_KT:
		out.append(_item("weather", "bad", "tailwind", "Tailwind %d kt on runway %s" % [maxi(roundi(tail), int(TAILWIND_KT) + 1), rwy.ident]))
	var lim := max_crosswind_kt(ac)
	var cross := absf(w.y)
	if cross > lim:
		out.append(_item("weather", "bad", "crosswind", "Crosswind %d kt, above %d kt" % [maxi(roundi(cross), int(lim) + 1), int(lim)]))


static func _load_runways() -> Array:
	if _runways.is_empty() and FileAccess.file_exists(Paths.data("runways.json")):
		var d = Paths.load_json("runways.json")
		if d is Dictionary:
			_runways = d.get("runways", [])
	return _runways
