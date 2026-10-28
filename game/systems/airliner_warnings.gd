class_name AirlinerWarnings
extends Node
## E/WD memo and warning lines of an airliner, built from Props (ui/displays/ewd.gd reads them). Ten times a
## second. Warnings are sorted red before amber, each by priority; memo lines are green.
## Warnings: ENG n FIRE, ELEC EMER CONFIG, STALL, CONFIG (take-off: park brake / flaps / speed brake), L/G GEAR NOT
## DOWN (gear not down below gear_warn_ft RA with flaps 3 or more, or thrust at idle), OVERSPEED (red);
## ENG n FAIL (latched once the engine ran, cleared by its master off), HYD G / B / Y SYS LO PR, ELEC AC BUS n FAULT,
## ELEC GEN n FAULT, FUEL L / R WING TK LO LVL (amber). Hydraulic and electrical faults only show with an engine
## running or in the air.
## The aircraft's aircraft.json "systems.warnings" over DEFAULTS: vmo_kt, mmo, takeoff_lever (thrust lever
## position that counts as take-off thrust), gear_warn_ft, gen_n2_min (percent), engine_run_n2 (percent).
## Reads: engines/<n>/{running, n2}, controls/engine_master_<n>, controls/throttle_1, controls/{parking_brake,
##   autobrake, spoilers_armed, signs/seatbelts, signs/no_smoking, lights/landing}, failures/engine_fire[_<n>],
##   fdm/{wow, agl_m, cas_mps, mach, gear_pos, flap_lever, speedbrake, stall_warning}, hyd/low_{g, b, y},
##   icing/ice_detected, controls/anti_ice/{wing, eng_1, eng_2} (memo ICE DETECTED / ANTI ICE),
##   systems/electrical/{ac1_on, ac2_on, gen1_on, gen2_on, emer}, fuel/low_{left, right}, apu/running.
## Publishes ewd/warnings and ewd/memo (arrays of [text, colour]: what EWD draws), ewd/warnings_text and
##   ewd/memo_text (the same lines joined with "\n"), ewd/master_warning (any red), ewd/master_caution (any amber).

const DEFAULTS := {
	"vmo_kt": 350.0, "mmo": 0.82, "takeoff_lever": 0.7, "gear_warn_ft": 1000.0, "gen_n2_min": 50.0, "engine_run_n2": 20.0,
}
const PERIOD := 0.1

var def: AircraftDef
var _p := DEFAULTS.duplicate(true)
var _n := 2
var _was_running: Array = []  # per engine: ran since its master went on
var _t := 0.0


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)
	if def == null:
		def = AircraftDef.current()
	_p = def.section_or("warnings", DEFAULTS)
	_n = def.engine_count()
	_was_running = []
	_was_running.resize(_n)
	_was_running.fill(false)


func save_key() -> String:
	return "airliner_warnings"


func save_state() -> Dictionary:
	return {"was_running": _was_running.duplicate()}


func load_state(d: Dictionary) -> void:
	var a = d.get("was_running", null)
	if a is Array:
		for i in mini(a.size(), _n):
			_was_running[i] = bool(a[i])


func _physics_process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = PERIOD
	update()


func update() -> void:
	var w := _warnings()
	w.sort_custom(func(a, b): return a[0] > b[0])
	var lines := []
	var memo := _memo()
	var red := false
	var amber := false
	for e in w:
		lines.append([e[1], e[2]])
		red = red or e[2] == "red"
		amber = amber or e[2] == "amber"
	Props.set_v("ewd/warnings", lines)
	Props.set_v("ewd/memo", memo)
	Props.set_v("ewd/warnings_text", "\n".join(lines.map(func(l): return l[0])))
	Props.set_v("ewd/memo_text", "\n".join(memo.map(func(l): return l[0])))
	Props.set_v("ewd/master_warning", red)
	Props.set_v("ewd/master_caution", amber)


func _running(n: int) -> bool:
	return Props.get_b("engines/%d/running" % n) or Props.get_f("engines/%d/n2" % n) >= _p.engine_run_n2


## [[priority, text, colour]] (red warnings have priorities above 60, amber below).
func _warnings() -> Array:
	var out := []
	var wow := Props.get_b("fdm/wow", true)
	var any_run := false
	for n in range(1, _n + 1):
		var run := _running(n)
		any_run = any_run or run
		var master := Props.get_b("controls/engine_master_%d" % n)
		_was_running[n - 1] = Props.get_b("engines/%d/running" % n) or (_was_running[n - 1] and master)
		if Props.get_b("failures/engine_fire" + ("" if n == 1 else "_%d" % n)):
			out.append([100, "ENG %d FIRE" % n, "red"])
		if _was_running[n - 1] and master and not Props.get_b("engines/%d/running" % n):
			out.append([50, "ENG %d FAIL" % n, "amber"])
		if run and n <= 2 and not Props.get_b("systems/electrical/gen%d_on" % n, true) \
				and Props.get_f("engines/%d/n2" % n) >= _p.gen_n2_min:
			out.append([44, "ELEC GEN %d FAULT" % n, "amber"])
	var live := any_run or not wow
	if Props.get_b("systems/electrical/emer"):
		out.append([90, "ELEC EMER CONFIG", "red"])
	if Props.get_b("fdm/stall_warning") or Props.get_b("fcs/stall_warning"):
		out.append([95, "STALL", "red"])
	if live:
		for k in ["g", "b", "y"]:
			if Props.get_b("hyd/low_" + k):
				out.append([40 - "gby".find(k), "HYD %s SYS LO PR" % k.to_upper(), "amber"])
		for k in [1, 2]:
			if not Props.get_b("systems/electrical/ac%d_on" % k, true):
				out.append([45, "ELEC AC BUS %d FAULT" % k, "amber"])
	for s in ["left", "right"]:
		if Props.get_b("fuel/low_" + s):
			out.append([35, "FUEL %s WING TK LO LVL" % s[0].to_upper(), "amber"])
	out.append_array(_flight_warnings(wow))
	return out


func _flight_warnings(wow: bool) -> Array:
	var out := []
	var cas_kt := Props.get_f("fdm/cas_mps") / Units.KT
	if cas_kt > _p.vmo_kt + 4.0 or Props.get_f("fdm/mach") > _p.mmo + 0.01:
		out.append([70, "OVERSPEED", "red"])
	var flap := roundi(Props.get_f("fdm/flap_lever"))
	if wow and Props.get_f("controls/throttle_1") >= _p.takeoff_lever:
		if Props.get_b("controls/parking_brake"):
			out.append([85, "CONFIG PARK BRK NOT RELEASED", "red"])
		if flap == 0:
			out.append([85, "CONFIG FLAPS NOT IN T.O. CONFIG", "red"])
		if Props.get_f("fdm/speedbrake") > 0.05:
			out.append([85, "CONFIG SPD BRK NOT RETRACTED", "red"])
	var gear_pos: Variant = Props.get_v("fdm/gear_pos", 1.0)
	var down: bool = (gear_pos.min() if gear_pos is Array and not gear_pos.is_empty() else float(gear_pos)) > 0.95
	var agl_ft := Units.m_to_ft(Props.get_f("fdm/agl_m"))
	var idle := Props.get_f("controls/throttle_1") < 0.05 and Props.get_f("controls/throttle_2") < 0.05
	if not wow and not down and agl_ft < _p.gear_warn_ft and (flap >= 3 or (idle and agl_ft < 750.0)):
		out.append([80, "L/G GEAR NOT DOWN", "red"])
	return out


func _memo() -> Array:
	var m := []
	var gear_pos: Variant = Props.get_v("fdm/gear_pos", 1.0)
	var down: bool = (gear_pos.min() if gear_pos is Array and not gear_pos.is_empty() else float(gear_pos)) > 0.95
	if down and not Props.get_b("fdm/wow", true):
		m.append(["LDG GEAR DN", "green"])
	if Props.get_b("controls/signs/seatbelts"):
		m.append(["SEAT BELTS", "green"])
	if Props.get_b("controls/signs/no_smoking"):
		m.append(["NO SMOKING", "green"])
	if Props.get_b("controls/lights/landing"):
		m.append(["LDG LT", "green"])
	var ab := int(Props.get_v("controls/autobrake", 0))
	if ab > 0:
		m.append(["AUTO BRK " + ["LO", "MED", "MAX"][clampi(ab, 1, 3) - 1], "green"])
	if Props.get_f("fdm/speedbrake") > 0.05 or Props.get_f("controls/speedbrake") > 0.05:
		m.append(["SPEED BRK", "green"])
	if Props.get_b("controls/spoilers_armed"):
		m.append(["GND SPLRS ARMED", "green"])
	if Props.get_b("controls/parking_brake"):
		m.append(["PARK BRK", "green"])
	if Props.get_b("apu/running"):
		m.append(["APU AVAIL", "green"])
	var anti_ice: bool = Props.get_b("controls/anti_ice/wing") or Props.get_b("controls/anti_ice/eng_1") or Props.get_b("controls/anti_ice/eng_2")
	if Props.get_b("icing/ice_detected"):  # systems/icing.gd: amber until an anti-ice is on
		m.append(["ICE DETECTED", "green" if anti_ice else "amber"])
	if anti_ice:
		m.append(["ANTI ICE", "green"])
	return m
