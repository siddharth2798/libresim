extends Node
## Debug: the autoland numbers over a matrix of runways, winds, turbulence, weights and approach speeds, through the closed-loop rig
## (tests/af_ils_rig.gd). One line per run (touchdown point past the threshold, offset from the axis, sink rate, pitch, heading error,
## worst offset on the roll out) and a summary. Headless, muted:
##   godot --headless --audio-driver Dummy --path game res://tests/debug_autoland_sweep.tscn -- [--runs=24] [--seed=1]
## --runs=N takes the first N cases of the list below.
const CASES := [
	# apt, rwy, wind_rel_deg, wind_kt, turb, mass_kg (0 = as is), kias
	["VABB", "27", 0, 0, 0.0, 0, 140], ["VAPO", "28", 0, 0, 0.0, 0, 140],
	["VABB", "27", 90, 14, 0.33, 0, 140], ["VABB", "27", -90, 14, 0.33, 0, 140],
	["VAPO", "28", 90, 14, 0.33, 0, 140], ["VAPO", "28", -90, 14, 0.33, 0, 140],
	["VABB", "27", 60, 15, 0.33, 0, 140], ["VAPO", "28", -60, 15, 0.33, 0, 140],
	["VABB", "27", 0, 20, 0.5, 0, 140], ["VAPO", "28", 180, 8, 0.33, 0, 140],
	["VABB", "27", 90, 12, 0.33, 56500, 132], ["VAPO", "28", -90, 12, 0.33, 56500, 132],
	["VABB", "27", 90, 12, 0.33, 66000, 150], ["VAPO", "28", -90, 12, 0.33, 66000, 150],
	["VABB", "27", 0, 0, 0.0, 56500, 132], ["VAPO", "28", 0, 0, 0.0, 66000, 150],
	["VABB", "27", 45, 10, 0.33, 0, 135], ["VAPO", "28", -45, 10, 0.33, 0, 145],
	["VABB", "27", 120, 10, 0.33, 60000, 138], ["VAPO", "28", -120, 10, 0.33, 60000, 138],
	["VABB", "27", 90, 15, 0.5, 0, 140], ["VAPO", "28", -90, 15, 0.5, 0, 140],
	["VABB", "27", 0, 0, 0.0, 0, 132], ["VAPO", "28", 0, 0, 0.0, 0, 152],
]


func _ready() -> void:
	var a := {}
	for x in OS.get_cmdline_user_args():
		var kv := x.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else ""
	var db := NavDatabase.new()
	var n := mini(int(a.get("runs", CASES.size())), CASES.size())
	var worst := {"along_min": 1e9, "along_max": -1e9, "cross": 0.0, "vs": 0.0, "roll": 0.0}
	for k in n:
		var c: Array = CASES[k]
		var st := {}
		for s in db.ils:
			if str(s.airport) == c[0] and str(s.runway) == c[1]:
				st = s
		var o := {"nm": 5.0, "kias": float(c[6]), "wind_rel_deg": float(c[2]), "wind_kt": float(c[3]), "turb": float(c[4]), "mass_kg": float(c[5]),
			"seed": int(a.get("seed", 1)) + k}
		var r := AfIlsRig.new(db, st, o)
		var m := r.f.mb.mass
		var rolled := 0.0
		while r.t < 400.0 and not r.crashed:
			r.step()
			if r.f.gear.wow:
				Props.set_v("controls/autobrake", 2)
				Props.set_v("controls/speedbrake", 1.0)
				Props.set_v("controls/reverse_1", 0.1)
				Props.set_v("controls/reverse_2", 0.1)
			if not r.td.is_empty():
				rolled += AfIlsRig.DT
				if r.gs_kt() < 15.0 or rolled > 90.0:
					break
		var td := r.td
		if td.is_empty():
			print("%2d %s %s FAILED no touchdown (crashed %s), fma %s" % [k, c[0], c[1], r.crashed, r.fma_all()])
		else:
			print("%2d %s %s wind %4d/%2d turb %.2f %5.0f kg %3d kt | td along %4.0f m cross %5.1f m sink %4.0f fpm pitch %4.1f hdg err %4.1f gs %3.0f | roll out worst %4.1f m%s" % [
				k, c[0], c[1], c[2], c[3], c[4], m, c[6], td.along, td.cross, -td.vs_fpm, td.pitch, td.heading_err, td.gs_kt, r.max_cross,
				" CRASHED" if r.crashed else ""])
			worst.along_min = minf(worst.along_min, td.along)
			worst.along_max = maxf(worst.along_max, td.along)
			worst.cross = maxf(worst.cross, absf(td.cross))
			worst.vs = maxf(worst.vs, -td.vs_fpm)
			worst.roll = maxf(worst.roll, r.max_cross)
		r.free_all()
	print("SUMMARY %s" % [worst])
	get_tree().quit()
