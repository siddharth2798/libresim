extends Node
## Debug: an autoland through the closed-loop rig (tests/af_ils_rig.gd: real A320 FDM and fly-by-wire law, real autoflight, NavRadios,
## flat runway, wind and turbulence). Prints the FMA, height, sink and offsets once a second above 400 ft and four times a second
## below, then the touchdown and the roll out. Headless, muted, much faster than the flight scene:
##   godot --headless --audio-driver Dummy --path game res://tests/debug_autoland_rig.tscn -- --apt=VABB --rwy=27 [--nm=7] [--kias=140]
##     [--flaps=5] [--wind=270/12 | --windrel=90/12 (from the right of the runway)] [--turb=0.33] [--seed=1] [--mass=64000] [--alt=<ft above the runway>] [--off=<m right>] [--ap2=0]
##     [--hdg=<deg off>] [--brake=2] [--quiet]
## Autobrake and ground spoilers as a pilot sets them (autobrake 2 = MED, reverse idle once on the ground) unless --brake=0.


func _ready() -> void:
	var a := {}
	for x in OS.get_cmdline_user_args():
		var kv := x.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else ""
	var db := NavDatabase.new()
	var st := {}
	for c in db.ils:
		if str(c.airport) == str(a.get("apt", "VABB")) and str(c.runway) == str(a.get("rwy", "27")):
			st = c
	if st.is_empty():
		print("no ILS for %s %s" % [a.get("apt", "VABB"), a.get("rwy", "27")])
		get_tree().quit()
		return
	var o := {"nm": float(a.get("nm", 7.0)), "kias": float(a.get("kias", 140.0)), "flaps": int(a.get("flaps", 5)), "seed": int(a.get("seed", 1)),
		"turb": float(a.get("turb", 0.0)), "mass_kg": float(a.get("mass", 0.0)), "offset_m": float(a.get("off", 0.0)),
		"ap2": int(a.get("ap2", 1)) > 0, "hdg_off_deg": float(a.get("hdg", 0.0))}
	if a.has("alt"):
		o["alt_ft"] = float(a.alt)
	if a.has("wind"):
		var w := str(a.wind).split("/")
		o["wind_from_deg"] = float(w[0])
		o["wind_kt"] = float(w[1])
	if a.has("windrel"):
		var w2 := str(a.windrel).split("/")
		o["wind_rel_deg"] = float(w2[0])
		o["wind_kt"] = float(w2[1])
	var r := AfIlsRig.new(db, st, o)
	print("ILS %s %s %.2f MHz course %.1f thr h %.0f m" % [st.airport, st.runway, float(st.mhz), float(st.course_true), r.ground_m])
	print("mass %.0f kg, fuel %.0f kg, empty %.0f kg, point masses %s" % [r.f.mb.mass, r.f.mb.fuel_kg(), r.f.mb.empty_kg, r.f.mb.point_masses.map(func(p): return "%s %.0f" % [p.name, p.kg])])
	var brake := int(a.get("brake", 2))
	var next := 0.0
	var quiet := a.has("quiet")
	var rolled := 0.0
	while r.t < 600.0 and not r.crashed:
		r.step()
		if brake > 0 and r.f.gear.wow:
			Props.set_v("controls/autobrake", brake)
			Props.set_v("controls/speedbrake", 1.0)
			Props.set_v("controls/reverse_1", 0.1)
			Props.set_v("controls/reverse_2", 0.1)
		var ra := r.ra_ft()
		if r.t >= next and not quiet:
			next = r.t + (0.25 if ra < 120.0 or r.f.gear.wow else 2.0)
			print("t %6.1f %s CAS %3.0f gs %3.0f ra %6.1f vs %5.0f pitch %5.1f bank %5.1f hdg %5.1f along %6.0f cross %5.1f wow %d lev %.2f alpha %.1f nz %.2f" % [r.t, r.fma_all(),
				r.f.cas / AfIlsRig.KT, r.gs_kt(), ra, Props.get_f("fdm/vs_mps") / AfIlsRig.FT * 60.0, rad_to_deg(r.f.euler().y), rad_to_deg(r.f.euler().x),
				fposmod(rad_to_deg(r.f.euler().z) - rad_to_deg(r.course) + 180.0, 360.0) - 180.0, r.along(), r.cross(), int(r.f.gear.wow), Props.get_f("ap/cmd/lever_1"), rad_to_deg(r.f.alpha), Props.get_f("ap/cmd/nz_g")])
		if not r.td.is_empty():
			rolled += AfIlsRig.DT
			if r.gs_kt() < 12.0 or rolled > 90.0:
				break
	print("TOUCHDOWN %s" % [r.td])
	print("max cross after touchdown %.1f m, crashed %s, along at end %.0f m, gs %.0f kt" % [r.max_cross, r.crashed, r.along(), r.gs_kt()])
	r.free_all()
	get_tree().quit()
