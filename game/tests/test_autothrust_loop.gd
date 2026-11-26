extends Node
## Closed loops of the A320 autothrust and the SPD/MACH target with the real A320 FDM (tests/af_rig.gd; the logic cases are in
## tests/test_autothrust.gd): the levers stay where the pilot put them while A/THR flies, and a selected Mach is held through an
## open climb and an open descent.

const KEEP := ["controls/fcu/spd_mach", "controls/fcu/mach_sel", "controls/fcu/spd_kt", "atmosphere/pressure_pa", "ap/spd_preset"]
const MACH_TOL := 0.02  # Mach hold tolerance (about 12 kt of TAS) with the crude test control law (AfTestLaw)

var _saved := {}


func _keep() -> void:
	for k in KEEP:
		if not _saved.has(k):
			_saved[k] = Props.get_v(k) if Props.has(k) else null


func teardown() -> void:
	for k in _saved:
		if _saved[k] == null:
			Props._p.erase(k)
		else:
			Props.set_v(k, _saved[k])
	_saved.clear()


func test_levers_stay_put_while_the_autothrust_flies() -> String:
	var r := AfRig.new(250.0, 10000.0, 0.0)
	var cl := AfThrust.CL
	for n in 2:
		Props.set_v("controls/throttle_%d" % (n + 1), cl)
	Props.set_v("controls/throttle", cl)
	r.fcu("spd_kt", 280.0)
	r.fcu("athr", true)
	r.run(40.0)
	if not Props.get_b("ap/athr_active"):
		return "A/THR active with the levers in CL"
	if Props.get_f("controls/throttle_1") != cl or Props.get_f("controls/throttle_2") != cl:
		return "the thrust levers moved by themselves"
	if absf(Props.get_f("ap/cmd/lever_1") - cl) < 0.01 and absf(r.kias() - 280.0) > 3.0:
		return "A/THR is not commanding anything (%.1f kt)" % r.kias()
	return ""


func test_mach_hold_in_a_climb_and_a_descent() -> String:
	_keep()
	var r := AfRig.new(250.0, 24000.0, 0.0)
	for n in 2:
		Props.set_v("controls/throttle_%d" % (n + 1), AfThrust.CL)
	Props.set_v("controls/throttle", AfThrust.CL)
	var m0 := Props.get_f("fdm/mach")
	var target := snappedf(m0 + 0.03, 0.01)
	r.fcu("spd_mach", true)
	r.fcu("mach_sel", target)
	r.fcu("athr", true)
	r.fcu("alt_ft", 24000.0)
	r.run(1.0)
	r.fcu("ap1", true)
	r.run(1.0)
	r.fcu("alt_ft", 28000.0)
	r.fcu("vert_select", "OPEN")  # open climb
	var err := [0.0, 0.0]  # worst Mach error and the time of the first sample counted (a lambda captures by value)
	var climb_start := r.alt_ft()
	var t_on := r.t + 20.0  # let the pull-up settle first
	r.run(120.0, func(): err[0] = maxf(err[0], absf(Props.get_f("fdm/mach") - target)) if r.t > t_on else err[0])
	print("    Mach %.2f -> target %.2f; climb: Mach %.3f, %.0f ft (from %.0f), FMA [%s] [%s], worst error %.3f"
		% [m0, target, Props.get_f("fdm/mach"), r.alt_ft(), climb_start, r.fma("thrust"), r.fma("vertical").replace("\n", "/"), err[0]])
	if r.alt_ft() < climb_start + 1000.0:
		return "the open climb did not climb (%.0f ft)" % r.alt_ft()
	if err[0] > MACH_TOL:
		return "Mach held within %.3f in the climb, worst %.3f" % [MACH_TOL, err[0]]
	r.fcu("alt_ft", 22000.0)
	r.fcu("vert_select", "OPEN")  # open descent
	err[0] = 0.0
	var top := r.alt_ft()
	t_on = r.t + 20.0
	r.run(100.0, func(): err[0] = maxf(err[0], absf(Props.get_f("fdm/mach") - target)) if r.t > t_on else err[0])
	print("    descent: Mach %.3f, %.0f ft (from %.0f), FMA [%s] [%s], worst error %.3f" % [Props.get_f("fdm/mach"), r.alt_ft(), top,
		r.fma("thrust"), r.fma("vertical").replace("\n", "/"), err[0]])
	if r.alt_ft() > top - 1000.0:
		return "the open descent did not descend (%.0f ft)" % r.alt_ft()
	if err[0] > MACH_TOL:
		return "Mach held within %.3f in the descent, worst %.3f" % [MACH_TOL, err[0]]
	return ""
