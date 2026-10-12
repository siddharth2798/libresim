extends RefCounted
## Hands-off flight from a trimmed start (the e2e sweep's handsoff_* jobs): the fixed aileron / rudder tabs
## (controls.aileron_rigging 0.033 / rudder_rigging 0.004) balance the rolling moment at about 100 KIAS,
## and JSBSim's c172p with the same tabs behaves the same: below that speed the pilot's weight and the engine
## torque win and the nearly neutral spiral mode lets the bank grow slowly to the left.
## JSBSim 1.3.2 c172p (engIO360C, same rigging, 3000 ft, ISA, calm, solo), bank / heading change after 60 s:
##   90 KCAS -10.7 deg / -76 deg;  95 KCAS -4.7 / -32;  100 KCAS 0.0 / 0 (tools/18_compare_fdm.py setup_air).
## Ours is within a few degrees of that, so a real regression (rigging, trim, wind, gear or thrust changes)
## shows up here, in the pure FDM, long before the game-level e2e run.

const DT := 1.0 / 120.0
const KT := 0.514444
const FT := 0.3048


## Trim at 3000 ft and `kcas`, fly 60 s with no input at all. Returns {bank, dpsi, dalt_ft, kcas_end} (degrees).
func _hands_off(kcas: float) -> Dictionary:
	var f := FDM.new()
	f.engine.mixture = 1.0
	var tas := kcas * KT
	for i in 3:  # trim at TAS, then correct TAS so CAS hits the target (as tools/18_compare_fdm.py)
		f.set_airborne(0, 0, 3000.0 * FT, 0.0, tas)
		f.prop.rpm = 2300.0
		f.trim_level(tas)
		f.step(1e-4)
		tas *= kcas * KT / f.cas
	f.time = 0.0
	var alt0 := f.altitude()
	for i in int(60.0 / DT):
		f.step(DT * 0.5)
		f.step(DT * 0.5)
	return {"bank": rad_to_deg(f.euler().x), "dpsi": rad_to_deg(wrapf(f.euler().z, -PI, PI)),
		"dalt_ft": (f.altitude() - alt0) / FT, "kcas_end": f.cas / KT}


func test_handsoff_100_kias_stays_level() -> String:
	var r := _hands_off(100.0)
	print("    100 KCAS hands off 60 s: bank %.1f deg, heading %+.0f deg, altitude %+.0f ft, %.0f KCAS at the end (JSBSim 0 / 0)" % [r.bank, r.dpsi, r.dalt_ft, r.kcas_end])
	if absf(r.bank) > 5.0 or absf(r.dpsi) > 25.0:
		return "hands-off at 100 KIAS drifted: bank %.1f deg, heading change %.0f deg (rigging is neutral here, JSBSim 0 / 0)" % [r.bank, r.dpsi]
	if absf(r.dalt_ft) > 100.0 or absf(r.kcas_end - 100.0) > 6.0:
		return "hands-off at 100 KIAS: altitude %+.0f ft, %.0f KCAS at the end" % [r.dalt_ft, r.kcas_end]
	return ""


func test_handsoff_90_kias_drifts_left_like_jsbsim() -> String:
	var r := _hands_off(90.0)
	print("    90 KCAS hands off 60 s: bank %.1f deg, heading %+.0f deg, altitude %+.0f ft (JSBSim -10.7 / -76)" % [r.bank, r.dpsi, r.dalt_ft])
	if r.bank > -6.0 or r.bank < -15.0:
		return "bank after 60 s %.1f deg, JSBSim -10.7 with the same rigging (expect -6 .. -15)" % r.bank
	if r.dpsi > -40.0 or r.dpsi < -105.0:
		return "heading change %.0f deg, JSBSim -76 with the same rigging (expect -40 .. -105)" % r.dpsi
	return ""
