class_name AirlinerHydraulics
extends Node
## Three hydraulic systems, GREEN / BLUE / YELLOW (A320-style), as pressures. GREEN has the engine 1 pump,
## YELLOW the engine 2 pump and an electric pump (AC 2), BLUE an electric pump (AC 1) that runs once an
## engine runs (or with the override). Engine pumps follow N2 (nothing below edp_n2_lo percent, full
## pressure from edp_n2_full). The power transfer unit (PTU) lifts the lower of GREEN / YELLOW to ptu_frac
## of the higher one when they differ by more than ptu_dp_psi. No RAT, no reservoirs; a failed system
## (failures/hyd_G, hyd_B, hyd_Y) loses its pumps and the PTU does not feed it.
## The numbers are the aircraft's aircraft.json "systems.hydraulics" over DEFAULTS: psi (normal pressure),
## ok_psi (usable), lo_psi (LO PR below), edp_n2_lo / edp_n2_full (percent), build_psi_s / decay_psi_s /
## leak_psi_s (pressure change rates), ptu_dp_psi, ptu_frac, spoiler_sys (the system of each spoiler panel).
## Switches (Props controls/hyd/*): green_edp, yellow_edp (default on), blue_epump (default on = AUTO),
##   blue_ovrd (run before an engine runs, default off), yellow_epump (default off), ptu (default on).
## Reads: engines/<n>/n2 (percent), systems/electrical/ac1_on / ac2_on (default on), failures/hyd_G|B|Y.
## Publishes systems/hydraulics/{green, blue, yellow}_pa and hyd/{green, blue, yellow}_psi, hyd/low_{g, b, y},
##   hyd/ptu_active, and for the consumers: systems/hydraulics/{antiskid (GREEN or YELLOW), gear_ok (GREEN),
##   flaps_ok (GREEN or BLUE), flaps_rate_factor (1 both, 0.5 one, 0 none), spoiler_ok (per panel, array),
##   brake_normal (GREEN), brake_alt (YELLOW), nws_ok (YELLOW), reverser_ok (per engine: GREEN, YELLOW)}.

const PSI := 6894.757
const SYS := ["green", "blue", "yellow"]
const DEFAULTS := {
	"psi": 3000.0, "ok_psi": 1500.0, "lo_psi": 1450.0, "edp_n2_lo": 8.0, "edp_n2_full": 40.0,
	"build_psi_s": 800.0, "decay_psi_s": 120.0, "leak_psi_s": 600.0, "ptu_dp_psi": 500.0, "ptu_frac": 0.8,
	"spoiler_sys": ["green", "yellow", "blue", "yellow", "green"],
}

var def: AircraftDef
var psi := {"green": 0.0, "blue": 0.0, "yellow": 0.0}
var ptu_active := false
var _p := DEFAULTS.duplicate(true)


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)
	if def == null:
		def = AircraftDef.current()
	_p = def.section_or("hydraulics", DEFAULTS)
	for k in ["green_edp", "yellow_edp", "blue_epump", "ptu"]:
		if not Props.has("controls/hyd/" + k):
			Props.set_v("controls/hyd/" + k, true)
	for k in ["blue_ovrd", "yellow_epump"]:
		if not Props.has("controls/hyd/" + k):
			Props.set_v("controls/hyd/" + k, false)


func save_key() -> String:
	return "airliner_hydraulics"


func save_state() -> Dictionary:
	return {"psi": psi.duplicate()}


func load_state(d: Dictionary) -> void:
	var s = d.get("psi", {})
	if s is Dictionary:
		for k in SYS:
			psi[k] = maxf(float(s.get(k, psi[k])), 0.0)


func _edp(n: int) -> float:  # engine-driven pump output, 0..1
	var n2 := Props.get_f("engines/%d/n2" % n)
	return clampf((n2 - _p.edp_n2_lo) / (_p.edp_n2_full - _p.edp_n2_lo), 0.0, 1.0)


func _dead(k: String) -> bool:
	return Props.get_b("failures/hyd_" + k[0].to_upper())


## Pressure each system is pushed towards (psi), before the PTU.
func _targets() -> Dictionary:
	var full: float = _p.psi
	var ac1 := Props.get_b("systems/electrical/ac1_on", true)
	var ac2 := Props.get_b("systems/electrical/ac2_on", true)
	var run := _edp(1) > 0.5 or _edp(2) > 0.5
	var blue_ep := Props.get_b("controls/hyd/blue_epump") and (run or Props.get_b("controls/hyd/blue_ovrd")) and ac1
	var yel_ep := Props.get_b("controls/hyd/yellow_epump") and ac2
	var t := {
		"green": full * _edp(1) if Props.get_b("controls/hyd/green_edp") else 0.0,
		"blue": full if blue_ep else 0.0,
		"yellow": maxf(full * _edp(2) if Props.get_b("controls/hyd/yellow_edp") else 0.0, full if yel_ep else 0.0),
	}
	for k in SYS:
		if _dead(k):
			t[k] = 0.0
	return t


func _physics_process(dt: float) -> void:
	var t := _targets()
	ptu_active = false
	if Props.get_b("controls/hyd/ptu", true) and not _dead("green") and not _dead("yellow"):
		var g: float = psi.green
		var y: float = psi.yellow
		if absf(g - y) > _p.ptu_dp_psi:
			var hi := maxf(g, y)
			if hi >= _p.ok_psi:
				ptu_active = true
				var low := "yellow" if g > y else "green"
				t[low] = maxf(t[low], hi * _p.ptu_frac)
	for k in SYS:
		var rate: float = _p.leak_psi_s if _dead(k) else (_p.build_psi_s if t[k] > psi[k] else _p.decay_psi_s)
		psi[k] = move_toward(psi[k], t[k], rate * dt)
	_publish()


func _ok(k: String) -> bool:
	return psi[k] >= _p.ok_psi


func _publish() -> void:
	var h := "systems/hydraulics/"
	for k in SYS:
		Props.set_v(h + k + "_pa", psi[k] * PSI)
		Props.set_v("hyd/%s_psi" % k, psi[k])
		Props.set_v("hyd/low_" + k[0], psi[k] < _p.lo_psi)
	Props.set_v("hyd/ptu_active", ptu_active)
	var g := _ok("green")
	var b := _ok("blue")
	var y := _ok("yellow")
	Props.set_v(h + "antiskid", g or y)
	Props.set_v(h + "gear_ok", g)
	Props.set_v(h + "flaps_ok", g or b)
	Props.set_v(h + "flaps_rate_factor", 1.0 if g and b else (0.5 if g or b else 0.0))
	Props.set_v(h + "brake_normal", g)
	Props.set_v(h + "brake_alt", y)
	Props.set_v(h + "nws_ok", y)
	Props.set_v(h + "reverser_ok", [g, y])
	var sp := []
	for k in _p.spoiler_sys:
		sp.append(_ok(str(k)))
	Props.set_v(h + "spoiler_ok", sp)
