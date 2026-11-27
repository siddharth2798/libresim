extends RefCounted
## Speed limits of the damage model (fdm/damage.gd) on the real aircraft data (aircraft/<id>/aircraft.json "limits"):
## going past VNE / VMO or VFE logs an inspection note but damages nothing; the airframe is damaged past VD and fails
## past VD x vd_fail_k; the flaps are damaged past VFE x flap_damage_k. The A320 keys VFE by slat + flap angle, so
## CONF 1 (slats only) has its own VFE (230 kt), blended between detents as the surfaces move. Each case holds a speed for 5 s (the model needs 2 s over a limit).

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
	_hold(f, 236.0, 15.0, 22.0)  # still under 1.2 x 200 = 240
	if f.damage.flaps_jammed:
		return "CONF 2 at 236 kt is under the damage speed (240): %s" % [f.damage.events]
	_hold(f, 245.0, 15.0, 22.0)
	return "" if f.damage.flaps_jammed else "CONF 2 at 245 kt (1.23 VFE) should damage the flaps"


func test_a320_conf1_slats_only_has_vfe_230() -> String:
	var f := _fdm("a320")
	if absf(f.damage.vfe_at(18.0) - 230.0) > 0.01 or absf(f.damage.vfe_at(28.0) - 215.0) > 0.01:
		return "VFE CONF 1 (slats 18) 230, 1+F (18 + 10) 215: %.0f / %.0f" % [f.damage.vfe_at(18.0), f.damage.vfe_at(28.0)]
	_hold(f, 250.0, 0.0, 18.0)  # CONF 1 over VFE 230, under 1.2 x 230 = 276
	if f.damage.flaps_jammed or not _noted(f, "Flaps"):
		return "CONF 1 at 250 kt: a note, no damage: jammed %s %s" % [f.damage.flaps_jammed, f.damage.events]
	_hold(f, 270.0, 0.0, 18.0)
	if f.damage.flaps_jammed:
		return "CONF 1 at 270 kt is under the damage speed (276)"
	_hold(f, 280.0, 0.0, 18.0)
	return "" if f.damage.flaps_jammed else "CONF 1 (slats out) at 280 kt should damage the slats / flaps"


## The bug of 2026-11-27: left in 1+F after takeoff, the A320 retracts to CONF 1 by itself at 210 kt and goes on
## accelerating while the flaps run in. The old step table kept 1+F's 215 until the flaps were fully in, so 218 kt with
## the flaps at 1.8 deg logged "Flaps over-sped" although the PFD's Vmax read 227.
func test_a320_flaps_running_in_have_the_pfd_limit() -> String:
	var f := _fdm("a320")
	var pfd := AirlinerAirData.spec_for(AircraftDef.load_def("a320").section("limits"))
	for flap in [10.0, 6.5, 4.1, 1.8, 0.0]:
		var v := f.damage.vfe_at(18.0 + flap)
		if absf(v - AirSpeeds.table(pfd.vfe_kt, 18.0 + flap)) > 0.01:
			return "slats 18 flaps %.1f: damage VFE %.1f, PFD %.1f: one table" % [flap, v, AirSpeeds.table(pfd.vfe_kt, 18.0 + flap)]
	if absf(f.damage.vfe_at(19.8) - 227.3) > 0.1:
		return "flaps 1.8 deg on their way in: VFE %.1f, want 227.3" % f.damage.vfe_at(19.8)
	_hold(f, 218.0, 1.8, 18.0)
	return "" if f.damage.events.is_empty() else "218 kt with the flaps nearly in is under the limit: %s" % [f.damage.events]


func test_a320_1f_and_full_damage_speeds() -> String:
	var f := _fdm("a320")
	_hold(f, 252.0, 10.0, 18.0)  # 1+F: VFE 215, damage over 258
	if f.damage.flaps_jammed:
		return "1+F at 252 kt is under the damage speed (258)"
	_hold(f, 262.0, 10.0, 18.0)
	if not f.damage.flaps_jammed:
		return "1+F at 262 kt should damage the flaps"
	var g := _fdm("a320")
	_hold(g, 208.0, 35.0, 27.0)  # FULL: VFE 177, damage over 212.4
	if g.damage.flaps_jammed:
		return "FULL at 208 kt is under the damage speed (212)"
	_hold(g, 216.0, 35.0, 27.0)
	return "" if g.damage.flaps_jammed else "FULL at 216 kt should damage the flaps"


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
	_hold(f, 98.0, 30.0)  # VFE 85, damage over 102
	if f.damage.flaps_jammed or not _noted(f, "Flaps"):
		return "flaps 30 at 98 kt: a note, no damage: %s" % [f.damage.events]
	_hold(f, 105.0, 30.0)
	if not f.damage.flaps_jammed:
		return "flaps 30 at 105 kt (1.24 VFE) should damage the flaps"
	var g := _fdm("c172")
	_hold(g, 128.0, 10.0)  # VFE 110 (10 deg), damage over 132
	if g.damage.flaps_jammed:
		return "flaps 10 at 128 kt is under the damage speed (132)"
	_hold(g, 175.0, 0.0)  # VNE 163, VD 185
	if g.damage.structure_damaged or not _noted(g, "airframe"):
		return "175 kt (VNE + 12): a note, no damage: %s" % [g.damage.events]
	_hold(g, 195.0, 0.0)
	if not g.damage.structure_damaged or g.damage.crashed:
		return "195 kt (over VD 185) should damage, not break, the airframe: %s" % [g.damage.events]
	_hold(g, 225.0, 0.0, 0.0, 0.1)  # over 1.2 x 185 = 222
	return "" if g.damage.crashed else "225 kt (over 1.2 VD) should break the airframe"


func test_flap_marks_for_the_speed_indicators() -> String:
	var c172 := AircraftDef.load_def("c172").section("limits")
	var m: Array = FlapSpeeds.marks(c172, [0.0, 10.0, 20.0, 30.0])
	if m != [[110.0, "10°"], [85.0, "20-30°"]]:
		return "C172 ASI flap marks: 110 at 10 deg, 85 for 20-30 deg: %s" % [m]
	var spec := AirlinerAirData.spec_for(AircraftDef.load_def("a320").section("limits"))
	var a: Array = AirSpeeds.vfe_marks(spec, ["0", "1", "1+F", "2", "3", "FULL"])
	if a != [[230.0, "1"], [215.0, "1+F"], [200.0, "2"], [185.0, "3"], [177.0, "FULL"]]:
		return "A320 PFD flap marks, one per detent: %s" % [a]
	return ""
