extends Node
## Debug: glide slope capture on every ILS station of the NavDatabase through the closed-loop rig (tests/af_ils_rig.gd): 8 nm out, level
## below the path (by --below metres, default 250) with LOC / APPR armed and both APs on; prints whether and when G/S* and G/S appear.
##   godot --headless --audio-driver Dummy --path game res://tests/debug_gs_sweep.tscn -- [--below=250] [--apt=VAPO --rwy=28] [--nm=8] [--max=4]


func _ready() -> void:
	var a := {}
	for x in OS.get_cmdline_user_args():
		var kv := x.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else ""
	var db := NavDatabase.new()
	var n := 0
	for st in db.ils:
		if a.has("apt") and (str(st.airport) != str(a.apt) or str(st.runway) != str(a.get("rwy", st.runway))):
			continue
		if n >= int(a.get("max", 4)):
			break
		n += 1
		var nm := float(a.get("nm", 8.0))
		var below := float(a.get("below", 250.0))
		var path_ft := tan(deg_to_rad(float(st.gs_deg))) * nm * 1852.0 / 0.3048 + 50.0
		var r := AfIlsRig.new(db, st, {"nm": nm, "alt_ft": path_ft - below / 0.3048, "kias": 140.0})
		var seen := {}
		var last := ""
		while r.t < 300.0 and not r.crashed and not seen.has("LAND"):
			r.step()
			var v := r.fma("vertical").replace("G/S", "GS").split("/")[0]
			if v != last:
				last = v
				seen[v] = r.t
		print("%s %s %.2f MHz gs %.2f: %s" % [st.airport, st.runway, float(st.mhz), float(st.gs_deg), seen])
		r.free_all()
	get_tree().quit()
