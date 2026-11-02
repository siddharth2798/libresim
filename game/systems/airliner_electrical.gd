class_name AirlinerElectrical
extends Node
## Electrical network of an airliner (A320-style): 115 V AC buses AC 1 / AC 2 / AC ESS, 28 V DC buses
## DC 1 / DC 2 / DC ESS / DC BAT, two engine generators, an APU generator, ground power, two TRs, two
## batteries and a static inverter. Which bus is powered comes from AirlinerBusLogic.solve; this node adds
## the sources (generators need N2 >= gen_n2_min percent), the batteries (charge off a TR, otherwise carry
## the DC BAT / DC ESS loads and the inverter) and the Props the rest of the game reads. No emergency
## generator (RAT) is modelled: with both engine generators lost the batteries carry on.
## The numbers are the aircraft's aircraft.json "systems.electrical" over DEFAULTS: battery_ah, bat_v_empty /
## bat_v_full (open circuit), bat_ohm, charge_gain / charge_min_a / charge_max_a (per battery), dc_volts
## (TR output), ac_volts, gen_n2_min (percent), gen_kva (for the load percentages), inverter_eff, low_volts,
## powered_volts, loads (W per consumer, see DEFAULTS).
## Switches (Props controls/electrical/*, all default on): bat1, bat2, gen1, gen2, apu_gen, ext_pwr.
## Reads: engines/<n>/n2 (percent), apu/running, ground/gpu_connected (ground power truck there),
##   controls/lights/*, systems/hydraulics/flaps_ok (default true), failures/{gen1, gen2, apu_gen, apu, battery,
##   battery_1, battery_2}.
## Publishes systems/electrical/{ac1, ac2, ac_ess, dc1, dc2, dc_ess, dc_bat}_on (bool) and _v (volts), *_src
##   (names of the source), bus_volts (DC BAT), battery_amps (net, + charging), soc (mean), bat1_soc, bat2_soc,
##   bat1_v, bat2_v, gen1_on, gen2_on, apu_gen_on, ext_on, gen<n>_load_pct, apu_gen_load_pct, ext_load_pct, emer (no AC 1 and
##   AC 2 in flight), and for the existing consumers: powered (AC ESS), avionics_powered (AC ESS),
##   gauges_powered, tc_powered (DC ESS), flaps_powered (DC ESS and hydraulics flaps_ok), starter_ok (DC BAT),
##   low_volts.

const DEFAULTS := {
	"battery_ah": 23.0, "bat_v_empty": 22.0, "bat_v_full": 26.5, "bat_ohm": 0.04,
	"charge_gain": 30.0, "charge_min_a": 0.5, "charge_max_a": 25.0,
	"dc_volts": 28.0, "ac_volts": 115.0, "gen_n2_min": 50.0, "gen_kva": 90.0, "inverter_eff": 0.8,
	"low_volts": 25.0, "powered_volts": 20.0,
	"loads": {  # W
		"dc_bat": 100.0, "dc_ess": 250.0, "ac_ess": 500.0, "ac_bus": 12000.0,
		"nav": 80.0, "beacon": 60.0, "strobe": 100.0, "landing": 1200.0, "taxi": 250.0, "wing": 150.0,
		"logo": 100.0, "rwy_turnoff": 250.0, "panel": 40.0,
	},
}
const SWITCHES := ["bat1", "bat2", "gen1", "gen2", "apu_gen", "ext_pwr"]
const BUSES := ["ac1", "ac2", "ac_ess", "dc1", "dc2", "dc_ess", "dc_bat"]

var def: AircraftDef  # tests set it; otherwise the current aircraft
var soc := [0.9, 0.9]  # battery state of charge 0..1
var bus := {}  # the last AirlinerBusLogic.solve result
var _p := DEFAULTS.duplicate(true)


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)
	if def == null:
		def = AircraftDef.current()
	_p = def.section_or("electrical", DEFAULTS)
	for k in SWITCHES:
		if not Props.has("controls/electrical/" + k):
			Props.set_v("controls/electrical/" + k, true)


func save_key() -> String:
	return "airliner_electrical"


func save_state() -> Dictionary:
	return {"soc": soc.duplicate()}


func load_state(d: Dictionary) -> void:
	var s = d.get("soc", soc)
	if s is Array and s.size() >= 2:
		soc = [clampf(float(s[0]), 0.0, 1.0), clampf(float(s[1]), 0.0, 1.0)]


func _sw(name: String) -> bool:
	return Props.get_b("controls/electrical/" + name, true)


func _gen(n: int) -> bool:
	return _sw("gen%d" % n) and not Props.get_b("failures/gen%d" % n) \
		and Props.get_f("engines/%d/n2" % n) >= _p.gen_n2_min


func _bat_on(i: int) -> bool:
	var failed := Props.get_b("failures/battery") or Props.get_b("failures/battery_%d" % (i + 1))
	return _sw("bat%d" % (i + 1)) and not failed and soc[i] > 0.0


## Watts on the DC BAT / DC ESS buses and the AC ESS bus (lights count on AC ESS).
func _loads(b: Dictionary) -> Dictionary:
	var ac_ess: float = _p.loads.ac_ess if b.ac_ess else 0.0
	if b.ac_ess:
		for l in ["nav", "beacon", "strobe", "landing", "taxi", "wing", "logo", "rwy_turnoff", "panel"]:
			if Props.get_b("controls/lights/" + l):
				ac_ess += _p.loads[l]
	return {"dc_bat": _p.loads.dc_bat if b.dc_bat else 0.0, "dc_ess": _p.loads.dc_ess if b.dc_ess else 0.0, "ac_ess": ac_ess}


func _physics_process(dt: float) -> void:
	var on := [_bat_on(0), _bat_on(1)]
	var gens := [_gen(1), _gen(2)]
	var apu := Props.get_b("apu/running") and _sw("apu_gen") and not Props.get_b("failures/apu_gen") and not Props.get_b("failures/apu")
	var ext := Props.get_b("ground/gpu_connected") and _sw("ext_pwr")
	bus = AirlinerBusLogic.solve({"gen1": gens[0], "gen2": gens[1], "apu": apu, "ext": ext, "bat": on[0] or on[1]})
	var amps := _batteries(dt, on)
	var bat_v := [_bat_volts(0, on[0], amps[1]), _bat_volts(1, on[1], amps[1])]
	var dc_v: float = _p.dc_volts if bus.tr_charging else maxf(bat_v[0] if on[0] else 0.0, bat_v[1] if on[1] else 0.0)
	_publish(gens, apu, ext, on, bat_v, dc_v, amps[0])


## Battery currents: [net amps (+ charging), amps per connected battery]. Charging off a TR, else the
## batteries carry the DC BAT / DC ESS loads and the inverter (AC ESS).
func _batteries(dt: float, on: Array) -> Array:
	var n := int(on[0]) + int(on[1])
	if n == 0:
		return [0.0, 0.0]
	var net := 0.0
	var each := 0.0
	if bus.tr_charging:
		for i in 2:
			if on[i]:
				var c: float = clampf((1.0 - soc[i]) * _p.charge_gain + _p.charge_min_a, 0.0, _p.charge_max_a)
				soc[i] = clampf(soc[i] + c * dt / 3600.0 / _p.battery_ah, 0.0, 1.0)
				net += c
		each = net / n
	else:
		var l := _loads(bus)
		var w: float = l.dc_bat + l.dc_ess + l.ac_ess / _p.inverter_eff
		var v: float = lerpf(_p.bat_v_empty, _p.bat_v_full, (soc[0] + soc[1]) * 0.5)
		each = -w / v / n
		for i in 2:
			if on[i]:
				soc[i] = clampf(soc[i] + each * dt / 3600.0 / _p.battery_ah, 0.0, 1.0)
		net = each * n
	return [net, each]


func _bat_volts(i: int, on: bool, amps_each: float) -> float:
	if not on:
		return 0.0
	return lerpf(_p.bat_v_empty, _p.bat_v_full, soc[i]) - _p.bat_ohm * absf(amps_each)


func _publish(gens: Array, apu: bool, ext: bool, on: Array, bat_v: Array, dc_v: float, net_a: float) -> void:
	var b := "systems/electrical/"
	for k in BUSES:
		var up: bool = bus[k]
		Props.set_v(b + k + "_on", up)
		Props.set_v(b + k + "_v", (_p.ac_volts if k.begins_with("ac") else dc_v) if up else 0.0)
		Props.set_v(b + k + "_src", bus[k + "_src"] if bus.has(k + "_src") else "")
	Props.set_v(b + "gen1_on", gens[0])
	Props.set_v(b + "gen2_on", gens[1])
	Props.set_v(b + "apu_gen_on", apu)
	Props.set_v(b + "ext_on", ext)
	_publish_loads()
	Props.set_v(b + "bus_volts", dc_v if bus.dc_bat else 0.0)
	Props.set_v(b + "battery_amps", net_a)
	Props.set_v(b + "soc", (soc[0] + soc[1]) * 0.5)
	for i in 2:
		Props.set_v(b + "bat%d_soc" % (i + 1), soc[i])
		Props.set_v(b + "bat%d_v" % (i + 1), bat_v[i])
	var airborne := not Props.get_b("fdm/wow", true)
	Props.set_v(b + "emer", airborne and not bus.ac1 and not bus.ac2)
	Props.set_v(b + "powered", bus.ac_ess)
	Props.set_v(b + "avionics_powered", bus.ac_ess)
	Props.set_v(b + "gauges_powered", bus.dc_ess)
	Props.set_v(b + "tc_powered", bus.dc_ess)
	Props.set_v(b + "flaps_powered", bus.dc_ess and Props.get_b("systems/hydraulics/flaps_ok", true))
	Props.set_v(b + "starter_ok", bus.dc_bat)
	Props.set_v(b + "low_volts", not bus.tr_charging and (on[0] or on[1]) and dc_v < _p.low_volts)


## Generator / APU / ground power load: the AC bus load of every bus each source feeds, as percent of kVA.
func _publish_loads() -> void:
	var w := {}
	for k in ["ac1", "ac2"]:
		var src: String = bus[k + "_src"]
		if src != "":
			var s := "gen2" if src == "TIE" and k == "ac1" else ("gen1" if src == "TIE" else src.to_lower())
			w[s] = w.get(s, 0.0) + _p.loads.ac_bus
	for k in ["gen1", "gen2", "apu", "ext"]:
		var pct: float = w.get(k, 0.0) / (_p.gen_kva * 1000.0) * 100.0
		Props.set_v("systems/electrical/%s_load_pct" % ("apu_gen" if k == "apu" else k), pct)
