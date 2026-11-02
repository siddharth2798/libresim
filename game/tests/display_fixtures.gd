class_name DisplayFixtures
extends RefCounted
## Plausible Props for the glass displays (preview scene and tests): "cruise" = FL350 M0.78 on
## autopilot, "approach" = ILS final with gear down and CONF 3, "empty" = nothing published.


## Forget every prop the displays read (tests of "nothing published yet").
static func clear() -> void:
	for pre in ["instruments/", "ap/", "controls/fcu/", "controls/nd/", "controls/gps/", "mcdu/", "sd/", "avionics/", "engines/", "fdm/", "fuel/", "ewd/"]:
		for k in Props.dump(pre):
			Props._p.erase(k)


static func set_state(name: String) -> void:
	clear()
	if name == "empty":
		return
	var cruise := name == "cruise"
	var spd := AirSpeeds.spec_of({})
	var ias := 280.0 if cruise else 138.0
	var alt := 35000.0 if cruise else 1450.0
	var mk := AirSpeeds.markers(spd, 62000.0, 0.0 if cruise else 42.0, not cruise, 23842.0 if cruise else 97000.0)
	var v := {
		"instruments/adirs/valid": true, "instruments/adirs/pitch_rad": deg_to_rad(2.5 if cruise else 3.0),
		"instruments/adirs/roll_rad": deg_to_rad(8.0 if cruise else -3.0), "instruments/adirs/heading_deg": 70.0 if cruise else 272.0,
		"instruments/adirs/track_deg": 73.0 if cruise else 270.0, "instruments/adirs/slip": 0.2,
		"instruments/pfd/valid": true, "instruments/pfd/ias_kt": ias, "instruments/pfd/mach": 0.78 if cruise else 0.21,
		"instruments/pfd/tas_kt": 455.0 if cruise else 142.0, "instruments/pfd/trend_kt": 6.0 if cruise else -8.0,
		"instruments/pfd/vls_kt": mk.vls, "instruments/pfd/vsw_kt": mk.vsw, "instruments/pfd/vmax_kt": mk.vmax,
		"instruments/pfd/alt_ft": alt, "instruments/pfd/baro_hpa": 1013.25 if cruise else 1009.0,
		"instruments/pfd/baro_std": cruise, "instruments/pfd/vs_fpm": 0.0 if cruise else -700.0,
		"instruments/pfd/ra_ft": -1.0 if cruise else 1430.0,
		"controls/fcu/spd_kt": 280.0 if cruise else 138.0, "controls/fcu/hdg_deg": 70.0 if cruise else 272.0,
		"controls/fcu/alt_ft": 35000.0 if cruise else 1500.0, "controls/fcu/vs_fpm": 0.0, "controls/fcu/spd_managed": cruise,
		"controls/fcu/ap1": true, "controls/fcu/athr": true, "controls/fcu/appr": not cruise,
		"ap/ap1": true, "ap/ap2": not cruise, "ap/athr": true, "ap/fd": true, "ap/loc": not cruise, "ap/appr": not cruise,
		"ap/fd_pitch_rad": deg_to_rad(3.5 if cruise else 1.0), "ap/fd_roll_rad": deg_to_rad(10.0 if cruise else -1.0),
		"ap/fma/thrust": "MACH" if cruise else "SPEED", "ap/fma/vertical": "ALT CRZ" if cruise else "G/S",
		"ap/fma/lateral": "NAV" if cruise else "LOC", "ap/fma/approach": "" if cruise else "CAT 1\nDH 200",
		"ap/thrust_limit": "CLB" if cruise else "", "ap/n1_target": 0.88 if cruise else 0.55,
		"instruments/engines/count": 2,
		"fdm/groundspeed_mps": Units.kt_to_mps(430.0 if cruise else 132.0), "fdm/position_enu": Vector3.ZERO,
		"fdm/flap_lever": 0 if cruise else 3, "fdm/flap_deg": 0.0 if cruise else 20.0, "fdm/slat_deg": 0.0 if cruise else 22.0,
		"fdm/gear_pos": 0.0 if cruise else 1.0, "fuel/total_kg": 15800.0 if cruise else 5200.0,
		"fuel/tank_kg": [650.0, 2900.0, 6600.0 if cruise else 0.0, 2900.0, 650.0] if cruise else [400.0, 1900.0, 0.0, 1900.0, 400.0],
		"atmosphere/temperature_k": 218.0 if cruise else 285.0,
		"instruments/nd/wind_dir_deg": 280.0, "instruments/nd/wind_kt": 38.0 if cruise else 12.0,
		"instruments/nd/route": [{"id": "ABELO", "x": 48000.0, "y": 17000.0}, {"id": "VAPO", "x": 91000.0, "y": 5000.0}],
		"instruments/nd/near": [{"id": "VAPO", "x": 91000.0, "y": 5000.0, "kind": "apt"}, {"id": "VABB", "x": -20000.0, "y": -30000.0, "kind": "apt"},
			{"id": "PNE", "x": 62000.0, "y": 40000.0, "kind": "vor"}, {"id": "VAJJ", "x": 8000.0, "y": 60000.0, "kind": "apt"}],
		"avionics/gps/valid": true, "avionics/gps/ident": "ABELO", "avionics/gps/dist_nm": 27.0, "avionics/gps/ete": "3:40",
		"controls/nd/range_nm": 80.0 if cruise else 20.0, "controls/nd/mode": 0 if cruise else 1,
		"controls/gps/target": "ABELO", "controls/gps/route_next": ["VAPO"], "controls/autobrake": 0 if cruise else 2,
	}
	if not cruise:
		v["avionics/nav2/kind"] = "ILS"
		v["avionics/nav2/valid"] = true
		v["avionics/nav2/cdi"] = 0.35
		v["avionics/nav2/gs"] = -0.25
		v["avionics/nav2/gs_valid"] = true
		v["avionics/nav2/ident"] = "IPNQ"
		v["avionics/nav2/dme_nm"] = 5.4
	for k in v:
		Props.set_v(k, v[k])
	for n in [1, 2]:
		var b := "instruments/engines/%d/" % n
		Props.set_v(b + "n1_pct", (86.5 if cruise else 52.0) + n * 0.2)
		Props.set_v(b + "n2_pct", 91.0 if cruise else 70.0)
		Props.set_v(b + "egt_c", 640.0 if cruise else 480.0)
		Props.set_v(b + "ff_kgh", 1150.0 if cruise else 780.0)
		Props.set_v(b + "oil_psi", 52.0)
		Props.set_v(b + "running", true)
