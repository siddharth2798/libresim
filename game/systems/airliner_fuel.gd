class_name AirlinerFuel
extends Node
## Fuel system of an airliner (A320-style tanks: outer / inner wing tank per side, a centre tank, and tiny
## "pipe" tanks in front of each engine and the APU that the FDM never draws from). Tank roles come from
## config.json "tanks" (pipe = capacity under 1 % of the total, centre = y ~ 0, wing tanks by side; on a side
## the innermost tank is the inner one, the others are outer ones) and "engines" (side by y).
## Which tank the burn is taken from (fuel/feed: per tank, fractions summing to 1, which fdm.tank_feed reads;
## pipe tanks always 0, so they just carry their fixed mass): the centre tank first while its pumps run and it
## has fuel, else each engine takes its own wing's inner tank (needs the wing pumps or, below
## gravity_ceiling_m, gravity); once the inner tank is below transfer_kg its outer tank is drawn instead, which
## is the net effect of the outer-to-inner transfer valves (the inner tank stays near transfer_kg until the
## outer one is empty). The crossfeed valve (controls/fuel/crossfeed) lets every engine draw from both wings.
## Each engine's share of the feed is its fuel flow (engines/<n>/ff; the APU's is apu/ff_kgs, from the
## apu_side wing), so a one-sided source gives one-sided burn.
## The numbers are the aircraft's aircraft.json "systems.fuel" over DEFAULTS: line_s (seconds an engine runs
## on its line after losing supply), low_kg (wing tank LO LVL), transfer_kg, leak_kg_per_h,
## gravity_ceiling_m, apu_side.
## Switches (Props controls/fuel/*): pump_left, pump_centre, pump_right (default on), crossfeed (default off).
## Reads: fuel/tank_kg (FDM), engines/<n>/ff, apu/ff_kgs, fdm/alt_m, systems/electrical/ac1_on / ac2_on
##   (pumps need AC power; absent = powered), failures/fuel_pump_<left|centre|right>, failures/fuel_leak_<left|right>.
## Publishes fuel/feed, fuel/leak_kgs, fuel/available (any engine fed: the existing FDM read),
##   fuel/available_<n> (engine n, 1-based; the FDM should use it per engine), fuel/available_apu,
##   fuel/pump_<left|centre|right> (running), fuel/low_<left|right> (wing total under low_kg), fuel/low (either),
##   fuel/used_kg (array, per engine), fuel/used_total_kg.

const DEFAULTS := {
	"line_s": 6.0, "low_kg": 750.0, "transfer_kg": 750.0, "leak_kg_per_h": 13.6,
	"gravity_ceiling_m": 7620.0, "apu_side": "left",
}
const SIDES := ["left", "right"]

var def: AircraftDef
var used: Array = []  # kg burnt per engine since the start
var _p := DEFAULTS.duplicate(true)
var _tank: Array = []  # per tank {side: left|right|centre|pipe, rank: 0 inner, 1.. outer, unusable_kg}
var _eng_side: Array = []  # per engine: left | right
var _line: Array = []  # per engine: line fuel left (s)


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)
	if def == null:
		def = AircraftDef.current()
	_p = def.section_or("fuel", DEFAULTS)
	_read_config(def.config())
	for k in ["left", "centre", "right"]:
		if not Props.has("controls/fuel/pump_" + k):
			Props.set_v("controls/fuel/pump_" + k, true)
	if not Props.has("controls/fuel/crossfeed"):
		Props.set_v("controls/fuel/crossfeed", false)


func _read_config(c: Dictionary) -> void:
	_tank.clear()
	var tanks: Array = c.get("tanks", [])
	var total := 0.0
	for t in tanks:
		total += float(t.capacity_kg)
	for t in tanks:
		var y: float = t.pos_m[1]
		var side := "pipe" if float(t.capacity_kg) < 0.01 * total else ("centre" if absf(y) <= 0.1 else ("left" if y < 0.0 else "right"))
		_tank.append({"side": side, "rank": 0, "y": absf(y), "unusable_kg": float(t.get("unusable_l", 0.0)) * float(t.get("density_kg_per_l", 0.8))})
	for s in SIDES:  # the innermost wing tank of a side is rank 0
		var ys := _tank.filter(func(t): return t.side == s).map(func(t): return t.y)
		ys.sort()
		for t in _tank:
			if t.side == s:
				t.rank = ys.find(t.y)
	_eng_side.clear()
	var engines: Array = c.get("engines", [])
	for i in engines.size():
		var y: float = engines[i].pos_m[1]
		_eng_side.append("left" if y < 0.0 or (y == 0.0 and i % 2 == 0) else "right")
	_line = _eng_side.map(func(_e): return float(_p.line_s))
	used = _eng_side.map(func(_e): return 0.0)


func save_key() -> String:
	return "airliner_fuel"


func save_state() -> Dictionary:
	return {"line": _line.duplicate(), "used": used.duplicate()}


func load_state(d: Dictionary) -> void:
	for k in ["line", "used"]:
		var a = d.get(k, null)
		if a is Array:
			var dst: Array = _line if k == "line" else used
			for i in mini(a.size(), dst.size()):
				dst[i] = float(a[i])


func _has_fuel(kg: Array, i: int) -> bool:
	return i < kg.size() and float(kg[i]) > _tank[i].unusable_kg


## Equal weights (sum 1) over tank indices.
static func _even(idx: Array) -> Dictionary:
	var out := {}
	for i in idx:
		out[i] = 1.0 / idx.size()
	return out


func _pump(role: String) -> bool:
	var ac := Props.get_b("systems/electrical/ac1_on", true) if role != "right" else Props.get_b("systems/electrical/ac2_on", true)
	if role == "centre":
		ac = Props.get_b("systems/electrical/ac1_on", true) or Props.get_b("systems/electrical/ac2_on", true)
	return Props.get_b("controls/fuel/pump_" + role, true) and not Props.get_b("failures/fuel_pump_" + role) and ac


func _centre_sources(kg: Array) -> Dictionary:
	if not _pump("centre"):
		return {}
	var idx := []
	for i in _tank.size():
		if _tank[i].side == "centre" and _has_fuel(kg, i):
			idx.append(i)
	return _even(idx)


## Tanks a wing's engine draws from (inner tank, or the outer one once the inner is below transfer_kg).
func _wing_sources(side: String, kg: Array) -> Dictionary:
	if not (_pump(side) or Props.get_f("fdm/alt_m") < _p.gravity_ceiling_m):
		return {}
	var inner := []
	var outer := []
	var inner_kg := 0.0
	for i in _tank.size():
		if _tank[i].side == side:
			if _tank[i].rank == 0:
				inner_kg += float(kg[i]) if i < kg.size() else 0.0
			if _has_fuel(kg, i):
				(inner if _tank[i].rank == 0 else outer).append(i)
	if not outer.is_empty() and (inner_kg < _p.transfer_kg or inner.is_empty()):
		return _even(outer)
	return _even(inner)


func _engine_sources(side: String, centre: Dictionary, wing: Dictionary, cross: bool) -> Dictionary:
	if not centre.is_empty():
		return centre
	var own: Dictionary = wing[side]
	var other: Dictionary = wing["right" if side == "left" else "left"]
	if cross and not other.is_empty():
		if own.is_empty():
			return other
		var out := {}
		for i in own:
			out[i] = out.get(i, 0.0) + own[i] * 0.5
		for i in other:
			out[i] = out.get(i, 0.0) + other[i] * 0.5
		return out
	return own


func _physics_process(dt: float) -> void:
	var tk = Props.get_v("fuel/tank_kg", null)
	var kg: Array = tk if tk is Array else []
	var centre := _centre_sources(kg)
	var wing := {"left": _wing_sources("left", kg), "right": _wing_sources("right", kg)}
	var cross := Props.get_b("controls/fuel/crossfeed")
	var src: Array = []  # per consumer (engines, then the APU): tank -> weight
	var flow: Array = []
	for i in _eng_side.size():
		src.append(_engine_sources(_eng_side[i], centre, wing, cross))
		flow.append(Props.get_f("engines/%d/ff" % (i + 1)))
		used[i] += flow[i] * dt
	src.append(_engine_sources(_p.apu_side, centre, wing, cross))
	flow.append(Props.get_f("apu/ff_kgs"))
	_publish(dt, kg, src, flow)


func _publish(dt: float, kg: Array, src: Array, flow: Array) -> void:
	var n := _eng_side.size()
	var feed: Array = []
	feed.resize(_tank.size())
	feed.fill(0.0)
	var total := 0.0
	for c in src.size():
		total += flow[c] if not src[c].is_empty() else 0.0
	for c in src.size():
		var share := 0.0
		if total > 1e-6:
			share = flow[c] / total
		elif c < n:  # nothing burning: split between the engines that have a supply
			share = 1.0 / maxf(src.slice(0, n).filter(func(s): return not s.is_empty()).size(), 1.0)
		for i in src[c]:
			feed[i] += share * src[c][i]
	var any := false
	for c in n:
		_line[c] = _p.line_s if not src[c].is_empty() else maxf(_line[c] - dt, 0.0)
		var up: bool = not src[c].is_empty() or _line[c] > 0.0
		any = any or up
		Props.set_v("fuel/available_%d" % (c + 1), up)
	Props.set_v("fuel/available_apu", not src[n].is_empty())
	Props.set_v("fuel/available", any)
	Props.set_v("fuel/feed", feed)
	_publish_misc(kg)


func _publish_misc(kg: Array) -> void:
	var leak: Array = []
	var side_kg := {"left": 0.0, "right": 0.0}
	for i in _tank.size():
		var s: String = _tank[i].side
		leak.append(_p.leak_kg_per_h / 3600.0 if s in SIDES and Props.get_b("failures/fuel_leak_" + s) else 0.0)
		if s in SIDES and i < kg.size():
			side_kg[s] += float(kg[i])
	Props.set_v("fuel/leak_kgs", leak)
	for r in ["left", "centre", "right"]:
		Props.set_v("fuel/pump_" + r, _pump(r))
	var low_l: bool = not kg.is_empty() and side_kg.left < _p.low_kg  # (no tank data yet: no warning)
	var low_r: bool = not kg.is_empty() and side_kg.right < _p.low_kg
	Props.set_v("fuel/low_left", low_l)
	Props.set_v("fuel/low_right", low_r)
	Props.set_v("fuel/low", low_l or low_r)
	Props.set_v("fuel/used_kg", used.duplicate())
	Props.set_v("fuel/used_total_kg", used.reduce(func(a, b): return a + b, 0.0))
