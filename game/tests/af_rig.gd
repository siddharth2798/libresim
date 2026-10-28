class_name AfRig
extends RefCounted
## Closed-loop rig of tests/test_autoflight.gd: the A320 FDM (aircraft/a320 data, no aircraft.json yet)
## run by a real FdmNode (controls, the A/THR lever override, Props publishing), the Autoflight node, an
## optional NavRadios, and a crude TEST-ONLY control law (AfTestLaw) standing in for the fly-by-wire law:
## it turns ap/cmd/nz_g and ap/cmd/roll_rate_dps into surface commands.

const LIMITS := {"vne_kias": 350.0, "vd_kias": 400.0, "vfe_kias": [[10.5, 230.0], [15.5, 215.0], [20.5, 200.0], [1000.0, 177.0]],
	"g_pos": 2.5, "g_neg": -1.0}
const DAMAGE := {"hard_landing_ms": 2.5, "collapse_ms": 4.0, "nose_collapse_ms": 3.0, "main_load_w": 2.5, "nose_load_w": 1.6}
const DT := 1.0 / 120.0
const KT := 0.514444
const FT := 0.3048

var node: FdmNode
var f: FDM
var af: Autoflight
var law: Object
var radios: NavRadios
var t := 0.0


## Airborne at `kias` / `alt_ft` on `heading_deg`, trimmed, engines on, gear and flaps as given, levers
## where the trim found them (or at CL when `cl_levers`).
func _init(kias := 250.0, alt_ft := 10000.0, heading_deg := 0.0, flap_lever := 0, gear_down := false, law_obj: Object = null) -> void:
	var def := AircraftDef.make("a320", {"limits": LIMITS, "damage": DAMAGE}, "res://aircraft/a320")
	f = FDM.new(def)
	node = FdmNode.new()
	node.fdm = f
	var alt_m := alt_ft * FT
	f.atmo.update(alt_m)
	f.set_airborne(0.0, 0.0, alt_m, deg_to_rad(heading_deg), kias * KT)
	for u in f.units:
		u.warm_start(true)
	f.fcs.gear_cmd = 1 if gear_down else 0
	f.gear.gear_pos = 1.0 if gear_down else 0.0
	f.fcs.flap_cmd = flap_lever
	f.fcs.settle()
	f.trim_level_cas(kias * KT)
	for n in 2:
		Props.set_v("controls/engine_master_%d" % (n + 1), true)
		Props.set_v("controls/throttle_%d" % (n + 1), f.units[n].engine.throttle)
		Props.set_v("engines/%d/lever" % (n + 1), f.units[n].engine.throttle)
	Props.set_v("controls/throttle", f.units[0].engine.throttle)
	Props.set_v("controls/gear", 1 if gear_down else 0)
	Props.set_v("controls/flaps", flap_lever)
	Props.set_v("controls/pitch_trim", f.fcs.pitch_trim)
	Props.set_v("engine/count", 2)
	Props.set_v("controls/baro/std", true)
	Props.set_v("systems/electrical/avionics_powered", true)
	for k in ["ap1", "ap2", "athr", "loc", "appr", "spd_managed", "hdg_managed", "vs_managed", "ap_disc", "athr_disc"]:
		Props.set_v("controls/fcu/" + k, false)
	Props.set_v("controls/fcu/fd", true)
	Props.set_v("controls/fcu/vert_select", "")
	Props.set_v("controls/fcu/spd_kt", kias)
	Props.set_v("controls/fcu/hdg_deg", heading_deg - AfInputs.VAR_DEG)
	Props.set_v("controls/fcu/alt_ft", alt_ft)
	Props.set_v("controls/fcu/vs_fpm", 0.0)
	Props.set_v("ap/athr_active", false)
	Props.set_v("ap/cmd/takeover", false)
	Props.set_v("fcs/alpha_floor", false)
	Props.set_v("failures/ap", false)
	law = law_obj if law_obj else AfTestLaw.new()
	f.fcs.law = law
	af = Autoflight.new()
	af.setup({})
	node._snap()
	publish()


## fdm/* Props as FdmNode publishes them, then the autoflight reads them.
func publish() -> void:
	node._publish()
	Props.set_v("engine/count", 2)


func step(dt := 1.0 / 60.0) -> void:
	if radios:
		radios._physics_process(dt)
	af.tick(dt)
	node._physics_process(dt)
	t += dt


func run(seconds: float, each: Callable = Callable()) -> void:
	for k in int(seconds * 60.0):
		step()
		if each.is_valid() and each.call() == true:
			return


func kias() -> float:
	return f.cas / KT


func alt_ft() -> float:
	return -f.pos_d / FT


func fpm() -> float:
	return -f.velocity_ned().z / FT * 60.0


func hdg_deg() -> float:
	return fposmod(rad_to_deg(f.euler().z), 360.0)


func fcu(k: String, v: Variant) -> void:
	Props.set_v("controls/fcu/" + k, v)


func fma(col: String) -> String:
	return str(Props.get_v("ap/fma/" + col, ""))
