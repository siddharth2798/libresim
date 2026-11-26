extends RefCounted
## The cases around the autoland, closed loop with the real autoflight and fly-by-wire law (tests/af_ils_rig.gd): without the second AP
## there is no LAND (CAT1) and the AP disconnects at 50 ft with the warning as before; CONF 2 is no autoland configuration; the
## localizer lost in LAND disconnects with the warning (involuntary: stays on); TOGA in LAND is a go-around (SRS, climb, no autoland);
## the pilot can disconnect on the roll out (the AP lets go and stays off).

const B := preload("res://tests/autoland_test_base.gd")

var _b := B.new()
var _rigs: Array = []


func teardown() -> void:
	for r in _rigs:
		r.free_all()
	_rigs.clear()


func _rig(o := {}) -> AfIlsRig:
	var base := {"nm": 2.4, "kias": 140.0}
	base.merge(o, true)
	var r := AfIlsRig.new(_b.db(), _b.station("VABB", "27"), base)
	_rigs.append(r)
	return r


func test_one_autopilot_is_no_autoland_and_disconnects_at_50_ft() -> String:
	var r := _rig({"ap2": false})
	r.run(120.0, func(): return r.ra_ft() < 45.0)
	var c := Props.get_f("ap/disconnect_count")
	if r.crashed or r.ra_ft() >= 45.0:
		return "the approach did not reach 45 ft (ra %.0f)" % r.ra_ft()
	if "LAND" in r.words.vertical or "FLARE" in r.words.vertical:
		return "LAND with one AP: %s" % [r.words.vertical]
	if "CAT3 DUAL" in r.words.approach or not "CAT1" in r.words.approach:
		return "approach column with one AP: %s, want CAT1" % [r.words.approach]
	if Props.get_b("ap/ap1") or c < 1.0 or not Props.get_b("ap/disconnect_warning"):
		return "AP1 on %s, disconnects %.0f, warning %s: it disconnects at 50 ft with the warning" % [Props.get_b("ap/ap1"), c, Props.get_b("ap/disconnect_warning")]
	return ""


func test_conf_2_is_no_autoland_configuration() -> String:
	var r := _rig({"flaps": 3})
	r.run(120.0, func(): return r.ra_ft() < 45.0)
	if "LAND" in r.words.vertical or "CAT3 DUAL" in r.words.approach:
		return "autoland in CONF 2: %s %s" % [r.words.vertical, r.words.approach]
	return "" if not Props.get_b("ap/ap1") else "AP1 still on at 45 ft in CONF 2 (disconnects at 50 ft as before)"


func test_localizer_lost_in_land_disconnects_with_the_warning() -> String:
	var r := _rig()
	r.run(120.0, func(): return str(Props.get_v("ap/land_phase", "")) == "LAND" and r.ra_ft() < 300.0)
	if str(Props.get_v("ap/land_phase", "")) != "LAND":
		return "no LAND: %s" % r.fma_all()
	Props.set_v("controls/nav2/freq_mhz", 116.6)  # a VOR: the ILS is gone
	r.run(3.0)
	if Props.get_b("ap/ap1") or Props.get_b("ap/ap2") or not Props.get_b("ap/disconnect_warning") or str(Props.get_v("ap/land_phase", "")) != "":
		return "AP %s/%s, warning %s, phase '%s' after the localizer was lost at %.0f ft" % [Props.get_b("ap/ap1"), Props.get_b("ap/ap2"),
			Props.get_b("ap/disconnect_warning"), Props.get_v("ap/land_phase", ""), r.ra_ft()]
	return ""


func test_toga_in_land_is_a_go_around() -> String:
	var r := _rig()
	r.run(120.0, func(): return str(Props.get_v("ap/land_phase", "")) == "LAND" and r.ra_ft() < 200.0)
	if str(Props.get_v("ap/land_phase", "")) != "LAND":
		return "no LAND: %s" % r.fma_all()
	for k in ["controls/throttle", "controls/throttle_1", "controls/throttle_2"]:
		Props.set_v(k, 1.0)
	r.run(12.0)
	var vs := Props.get_f("fdm/vs_mps") / AfIlsRig.FT * 60.0
	if r.crashed or not r.f.gear.wow == false or r.fma("vertical").split("/")[0] != "SRS" or str(Props.get_v("ap/land_phase", "")) != "":
		return "go-around: FMA %s, phase '%s', wow %s" % [r.fma_all(), Props.get_v("ap/land_phase", ""), r.f.gear.wow]
	if vs < 500.0 or r.ra_ft() < 100.0:
		return "go-around does not climb: %.0f ft/min, %.0f ft" % [vs, r.ra_ft()]
	return "" if Props.get_b("ap/ap1") else "the AP drops in a go-around (SRS needs it)"


func test_the_pilot_disconnects_on_the_roll_out() -> String:
	var r := _rig()
	r.run(150.0, func(): return not r.td.is_empty())
	r.run(0.5)
	if r.td.is_empty() or not Props.get_b("ap/ap1") or r.fma("lateral") != "ROLL OUT":
		return "no ROLL OUT after the touchdown: %s" % r.fma_all()
	r.run(4.0)
	Props.set_v("controls/fcu/ap_disc", true)
	r.run(1.0)
	var off := not Props.get_b("ap/ap1") and not Props.get_b("ap/ap2") and r.fma("lateral") != "ROLL OUT"
	r.run(5.0)
	return "" if off and not r.crashed and not Props.get_b("ap/ap1") else "the AP did not stay off after the pilot's disconnect on the roll out"
