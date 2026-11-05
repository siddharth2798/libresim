extends RefCounted
## The A320's stall margin (docs/A320-STATUS.md "Deliberate deviation from the JSBSim data: stall (CLmax)"):
## the 1 g speed at alpha-max per flap / slat detent against the FMGC Vs1g table of the upstream data
## (Systems/a320-fmgc.xml), measured the way tools/23_a320_reference.py does: stabilised at the detent, idle thrust,
## full aft stick on the normal law, 40 s, CL = nz W / (q S) averaged over the last 5 s, V = sqrt(2 W / (rho0 S CL)).

const A := preload("res://tests/test_fbw_a320.gd")
const KT := 0.514444
const S_WING := 122.6
const DT := 1.0 / 60.0

## detent: [slat deg, flap deg, flap lever index, start KCAS, altitude ft, gear down, Vs1g table at 60 t, at 65 t (kt)]
const CASES := {
	"clean": [0.0, 0.0, 0, 190.0, 3000.0, false, 150.81, 156.76],
	"1": [18.0, 0.0, 1, 185.0, 8000.0, false, 124.84, 130.17],
	"1+F": [18.0, 10.0, 2, 170.0, 7000.0, false, 117.97, 122.96],
	"2": [22.0, 15.0, 3, 160.0, 6000.0, false, 110.94, 115.63],
	"3": [22.0, 20.0, 4, 150.0, 5000.0, true, 109.10, 113.75],
	"FULL": [27.0, 35.0, 5, 150.0, 5000.0, true, 106.01, 110.25],
}
const TOLERANCE := 0.025  # 2.5 % of the table (the goal is 2 %)


## {v1g_kt, table_kt, alpha_deg, cl, mass} of one detent.
func measure(name: String) -> Dictionary:
	var c: Array = CASES[name]
	var t := A.new()
	var f: FDM = t._cruise(c[3], c[4], c[2], c[5])
	f.fcs.slat_deg = c[0]
	f.fcs.flap_deg = c[1]
	f.trim_level(c[3] * KT * sqrt(1.225 / f.atmo.density))
	f.set_throttle(0.0)
	var v_prot := 0.0  # CAS (kt) where a hands-off, idle deceleration reaches alpha-prot (the oracle's kcas_at_alpha_prot_1g)
	for i in int(150.0 / DT):
		f.step(DT)
		if f.alpha >= t._law(f).prot.a_prot - deg_to_rad(0.1):
			v_prot = f.cas / KT
			break
	f.fcs.pitch = 1.0
	var n := 0
	var cl := 0.0
	var al := 0.0
	var cas := 0.0
	for i in int(40.0 / DT):
		f.step(DT)
		if i >= int(35.0 / DT):
			cl += t._law(f).s.nz * f.mb.mass * 9.80665 / (f.qbar * S_WING)
			al += f.alpha
			cas += f.cas
			n += 1
	cl /= n
	var m := f.mb.mass
	var w := clampf((m - 60000.0) / 5000.0, -0.5, 1.5)
	return {"v1g_kt": sqrt(2.0 * m * 9.80665 / (1.225 * S_WING * cl)) / KT, "table_kt": lerpf(c[6], c[7], w), "alpha_deg": rad_to_deg(al / n),
		"cl": cl, "mass": m, "v_prot_kt": v_prot, "cas_kt": cas / n / KT, "crashed": f.damage.crashed}


func _check(name: String) -> String:
	var r := measure(name)
	var err: float = r.v1g_kt / r.table_kt - 1.0
	var prot: float = r.v_prot_kt / r.table_kt
	print("    %s: 1 g speed at alpha-max %.1f kt (table %.1f kt, %+.1f %%), CL %.3f, alpha %.2f deg, %.1f t; alpha-prot speed %.1f kt = %.2f x table" % [
		name, r.v1g_kt, r.table_kt, err * 100.0, r.cl, r.alpha_deg, r.mass / 1000.0, r.v_prot_kt, prot])
	if r.crashed:
		return "%s: crashed" % name
	if absf(err) > TOLERANCE:
		return "%s: 1 g speed at alpha-max %.1f kt, FMGC table %.1f kt (%+.1f %%)" % [name, r.v1g_kt, r.table_kt, err * 100.0]
	return "" if prot > 1.06 and prot < 1.18 else "%s: alpha-prot speed %.1f kt is %.2f x the table Vs1g (want 1.06 to 1.18, real about 1.1 to 1.13)" % [name, r.v_prot_kt, prot]


func test_a320_stall_speed_clean() -> String:
	return _check("clean")


func test_a320_stall_speed_conf_1() -> String:
	return _check("1")


func test_a320_stall_speed_conf_1f() -> String:
	return _check("1+F")


func test_a320_stall_speed_conf_2() -> String:
	return _check("2")


func test_a320_stall_speed_conf_3() -> String:
	return _check("3")


func test_a320_stall_speed_conf_full() -> String:
	return _check("FULL")
