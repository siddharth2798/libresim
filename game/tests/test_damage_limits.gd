extends RefCounted
## Speed limits of the damage model (fdm/damage.gd) on the real aircraft data (aircraft/<id>/aircraft.json "limits"):
## going past VNE / VMO or VFE logs an inspection note but damages nothing; the airframe is damaged past VD and fails
## past VD x vd_fail_k; the flaps are damaged past VFE x flap_damage_k. The A320 keys VFE by slat + flap angle, so
## CONF 1 (slats only) has its own VFE (230 kt). Each case holds a speed for 5 s (the model needs 2 s over a limit).

const KT := 0.514444


func _fdm(id: String) -> FDM:
	return FDM.new(AircraftDef.load_def(id))


## Hold `kias` with flaps / slats at the given angles for `seconds`, through the damage model's air limits only.
func _hold(f: FDM, kias: float, flap_deg: float, slat_deg := 0.0, seconds := 5.0) -> void:
	f.fcs.flap_deg = flap_deg
	if "slat_deg" in f.fcs:
		f.fcs.set("slat_deg", slat_deg)
	f.cas = kias * KT
	f.flight_load_factor = 1.0
	for i in int(seconds * 120.0):
		f.damage._check_air_limits(f, 1.0 / 120.0)


func _noted(f: FDM, what: String) -> bool:
	return f.damage.events.any(func(e): return str(e).contains(what) and str(e).contains("inspection due"))


func test_a320_conf2_just_over_vfe_is_a_note_not_damage() -> String:
	var f := _fdm("a320")
	_hold(f, 205.0, 15.0, 22.0)  # CONF 2: VFE 200
	if f.damage.flaps_jammed:
		return "CONF 2 at 205 kt (VFE 200 + 5) must not damage the flaps: %s" % [f.damage.events]
	if not _noted(f, "Flaps"):
		return "CONF 2 at 205 kt should log a flap inspection note: %s" % [f.damage.events]
	_hold(f, 225.0, 15.0, 22.0)  # still under 1.15 x 200 = 230
	if f.damage.flaps_jammed:
		return "CONF 2 at 225 kt is under the damage speed (230): %s" % [f.damage.events]
	_hold(f, 236.0, 15.0, 22.0)
	return "" if f.damage.flaps_jammed else "CONF 2 at 236 kt (1.18 VFE) should damage the flaps"


func test_a320_conf1_slats_only_has_vfe_230() -> String:
	var f := _fdm("a320")
	if absf(f.damage.vfe_at(18.0) - 230.0) > 0.01 or absf(f.damage.vfe_at(28.0) - 215.0) > 0.01:
		return "VFE CONF 1 (slats 18) 230, 1+F (18 + 10) 215: %.0f / %.0f" % [f.damage.vfe_at(18.0), f.damage.vfe_at(28.0)]
	_hold(f, 250.0, 0.0, 18.0)  # CONF 1 over VFE 230, under 1.15 x 230 = 264.5
	if f.damage.flaps_jammed or not _noted(f, "Flaps"):
		return "CONF 1 at 250 kt: a note, no damage: jammed %s %s" % [f.damage.flaps_jammed, f.damage.events]
	_hold(f, 270.0, 0.0, 18.0)
	return "" if f.damage.flaps_jammed else "CONF 1 (slats out) at 270 kt should damage the slats / flaps"


func test_a320_1f_and_full_damage_speeds() -> String:
	var f := _fdm("a320")
	_hold(f, 240.0, 10.0, 18.0)  # 1+F: VFE 215, damage over 247
	if f.damage.flaps_jammed:
		return "1+F at 240 kt is under the damage speed (247)"
	_hold(f, 250.0, 10.0, 18.0)
	if not f.damage.flaps_jammed:
		return "1+F at 250 kt should damage the flaps"
	var g := _fdm("a320")
	_hold(g, 200.0, 35.0, 27.0)  # FULL: VFE 177, damage over 203.6
	if g.damage.flaps_jammed:
		return "FULL at 200 kt is under the damage speed (204)"
	_hold(g, 210.0, 35.0, 27.0)
	return "" if g.damage.flaps_jammed else "FULL at 210 kt should damage the flaps"


func test_a320_over_vmo_is_a_note_vd_damages_and_breaks() -> String:
	var f := _fdm("a320")
	_hold(f, 370.0, 0.0)  # VMO 350 + 20: inspection, VD 381
	if f.damage.structure_damaged or f.damage.crashed:
		return "370 kt (VMO + 20, under VD 381) must not damage the airframe: %s" % [f.damage.events]
	if not _noted(f, "airframe"):
		return "over VMO should log an airframe inspection note: %s" % [f.damage.events]
	_hold(f, 390.0, 0.0)
	if not f.damage.structure_damaged or f.damage.crashed:
		return "390 kt (over VD 381) should damage, not break, the airframe: %s" % [f.damage.events]
	_hold(f, 440.0, 0.0, 0.0, 0.1)  # over 1.15 x 381 = 438
	return "" if f.damage.crashed else "440 kt (over 1.15 VD) should break the airframe"


func test_c172_flap_and_airframe_margins() -> String:
	var f := _fdm("c172")
	_hold(f, 92.0, 30.0)  # VFE 85, damage over 97.75
	if f.damage.flaps_jammed or not _noted(f, "Flaps"):
		return "flaps 30 at 92 kt: a note, no damage: %s" % [f.damage.events]
	_hold(f, 100.0, 30.0)
	if not f.damage.flaps_jammed:
		return "flaps 30 at 100 kt (1.18 VFE) should damage the flaps"
	var g := _fdm("c172")
	_hold(g, 120.0, 10.0)  # VFE 110 (10 deg), damage over 126.5
	if g.damage.flaps_jammed:
		return "flaps 10 at 120 kt is under the damage speed (126.5)"
	_hold(g, 175.0, 0.0)  # VNE 163, VD 185
	if g.damage.structure_damaged or not _noted(g, "airframe"):
		return "175 kt (VNE + 12): a note, no damage: %s" % [g.damage.events]
	_hold(g, 195.0, 0.0)
	if not g.damage.structure_damaged or g.damage.crashed:
		return "195 kt (over VD 185) should damage, not break, the airframe: %s" % [g.damage.events]
	_hold(g, 225.0, 0.0, 0.0, 0.1)  # over 1.2 x 185 = 222
	return "" if g.damage.crashed else "225 kt (over 1.2 VD) should break the airframe"
