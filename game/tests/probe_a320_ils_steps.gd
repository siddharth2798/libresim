extends RefCounted
## Probe helper of probe_a320_ils.gd: the crew of an A320 ILS approach from high and far out (20 nm, 10,000 ft, 250 kt, clean),
## one step at a time, as the handbook tells a player (docs/site/index.html "An ILS approach from high and far out"). Every action
## is a cockpit action: an FCU button toggle, a knob turned (the window value) then pushed or pulled (ControlActions.SETS, the same
## writes as the keys), the flaps lever, the gear lever, the speedbrake lever and the autobrake. Nothing is written behind the
## cockpit's back. Each step checks what the player should see (the FMA, the lights) and records a verdict in `checks`.
## `managed` = the trap: managed speed and flaps out early in the descent, so the open descent slows level, reaches the FCU
## altitude above the glide slope and G/S cannot capture; the crew then recovers as the FCTM says (FCU altitude above the
## aircraft, V/S down through the beam). Reads one dictionary per tick (`s`, built by the probe).

const VFE := [999.0, 230.0, 215.0, 200.0, 185.0, 177.0]  # lever 0..5 (UP, 1, 1+F, 2, 3, FULL), kt
const INTERCEPT_FT := 3000.0  # the ATC descent (ATC: "descend 3000 feet, cleared ILS approach"); also its go-around altitude
const RECOVER_VS_FPM := -1500.0
const LEVERS := ["controls/throttle", "controls/throttle_1", "controls/throttle_2"]

var managed := false
var own_start := false  # the start screen's In the air: 160 kt, gear down, CONF 2 (managed speed; stay in CONF 2 for the speedbrake)
var step := "start"
var dip_kt := 0.0  # worst speed below the target in OP DES (the first 60 s, the speedbrake going out)
var checks: Array = []  # [step, ok, text]
var log: Array = []
var _t_step := 0.0
var _flaps := 0
var _gear := 0
var _sb := 0.0
var _seen := {}  # FMA words seen, and the once() keys


func say(t: float, msg: String) -> void:
	log.append("ILS %7.1f %s" % [t, msg])
	print(log.back())


func check(t: float, ok: bool, text: String) -> void:
	checks.append([step, ok, text])
	say(t, "%s [%s] %s" % ["OK  " if ok else "FAIL", step, text])


## A button on the FCU pressed to the state `on` (the key toggles it; the light shows what the autoflight accepted).
func button(k: String, on: bool) -> void:
	if Props.get_b("controls/fcu/" + k) != on:
		Props.set_v("controls/fcu/" + k, on)


## A knob push or pull: the same Props writes as the key (ControlActions.SETS).
func knob(action: String) -> void:
	var w: Dictionary = ControlActions.SETS[action]
	for k in w:
		Props.set_v(k, w[k])


## True the first time it is asked with `key` in this step (an action done once, a check made once).
func once(key: String) -> bool:
	var k := step + "/" + key
	if _seen.has(k):
		return false
	_seen[k] = true
	return true


func seen(w: String) -> bool:
	return _seen.has(w)


func _go(next: String, s: Dictionary) -> void:
	step = next
	_t_step = s.t
	say(s.t, "--- step %s (%.1f nm, %.0f ft, %.0f ft above the path, %.0f kt, FMA %s)" % [next, s.dest_nm, s.alt_ft,
		s.alt_ft - s.path_ft, s.ias, s.fma])


func decide(s: Dictionary) -> void:
	for w in [s.thr_fma, s.vert_fma, s.lat_fma, s.appr_fma]:
		for x in str(w).split("\n", false):
			_seen[x] = true
	var dt: float = s.t - _t_step
	if s.lat_fma.begins_with("LOC") and int(Props.get_v("controls/autobrake", 0)) == 0:  # handbook step 5: autobrake MED at LOC
		Props.set_v("controls/autobrake", 2)
		say(s.t, "LOC captured: autobrake MED")
	match step:
		"start":
			_flaps = int(Props.get_v("controls/flaps", 0))
			_gear = int(Props.get_v("controls/gear", 0))
			var want := [1, 3, 160.0] if own_start else [0, 0, 250.0]
			check(s.t, _gear == want[0] and _flaps == want[1] and absf(s.alt_ft - 10000.0) < 300.0 and absf(s.ias - want[2]) < 10.0,
				"gear %d, flaps %d, %.0f ft, %.0f kt (FMA %s)" % [_gear, _flaps, s.alt_ft, s.ias, s.fma])
			_go("engage", s)
		"engage": _engage(s, dt)
		"appr": _appr(s, dt)
		"descend": _descend(s, dt)
		"recover": _recover(s, dt)
		"glideslope": _glideslope(s, dt)
		"final": _final(s)
		"land": _land(s)
		"rollout":
			if s.gs < 1.0:
				_go("stopped", s)


## 1. ALT knob to the present altitude, levers to CL, A/THR, AP1: FMA SPEED / ALT / HDG.
func _engage(s: Dictionary, dt: float) -> void:
	if once("do"):
		Props.set_v("controls/fcu/alt_ft", roundf(s.alt_ft / 100.0) * 100.0)
		for k in LEVERS:
			Props.set_v(k, AfThrust.CL)
		button("athr", true)
		button("ap1", true)
		say(s.t, "ALT knob to %.0f, levers CL, A/THR on, AP1 on" % Props.get_f("controls/fcu/alt_ft"))
	elif dt > 4.0:
		check(s.t, Props.get_b("ap/ap1") and Props.get_b("ap/athr_active"), "AP1 and A/THR engaged (FMA %s)" % s.fma)
		check(s.t, s.thr_fma == "SPEED" and s.vert_fma.begins_with("ALT") and s.lat_fma == "HDG", "FMA SPEED / ALT / HDG, got %s" % s.fma)
		_go("appr", s)


## 2. LS on, APPR, AP2: arming APPR tunes the ILS of the runway ahead (no route), LOC and G/S armed, AP1+2.
func _appr(s: Dictionary, dt: float) -> void:
	if once("do"):
		Props.set_v("controls/efis/ls", true)
		button("appr", true)
		button("ap2", true)
		say(s.t, "LS on, APPR, AP2")
	elif dt > 2.0:
		check(s.t, str(Props.get_v("avionics/ils_auto/ident", "")) != "", "APPR tunes the ILS ahead: %s" % s.ils_auto)
		check(s.t, s.misc_fma.find("AP1+2") >= 0, "AP1+2 in column 5, got %s" % s.misc_fma)
		check(s.t, s.vert_fma.ends_with("\nG/S") and s.lat_fma.ends_with("\nLOC"), "G/S and LOC armed, got %s" % s.fma)
		_go("descend", s)


## 3. ALT knob to 3,000 ft and pull: OP DES, THR IDLE. Speed selected 250 kt (pulled), speedbrake by the height above the path.
## The trap (`managed`): SPD pushed and the flaps out on the way down. Next: G/S captured, or ALT above the beam (recover).
func _descend(s: Dictionary, dt: float) -> void:
	if once("do"):
		Props.set_v("controls/fcu/alt_ft", INTERCEPT_FT)
		knob("fcu_alt_pull")
		if managed or own_start:
			knob("fcu_spd_push")
		else:
			Props.set_v("controls/fcu/spd_kt", 250.0)
			knob("fcu_spd_pull")
		say(s.t, "ALT %.0f pulled, SPD %s" % [INTERCEPT_FT, "pushed (managed)" if managed or own_start else "250 pulled (selected)"])
		return
	if dt > 3.0 and once("check"):
		check(s.t, s.vert_fma.begins_with("OP DES") and s.thr_fma == "THR IDLE", "FMA THR IDLE / OP DES, got %s" % s.fma)
	if s.vert_fma.begins_with("OP DES") and dt > 2.0 and not managed:
		dip_kt = minf(dip_kt, s.ias - s.spd_tgt_kt)
	if dt > 60.0 and once("dip") and not managed:  # OP DES and the speedbrake at once: the push-over (0.2 g) lets the speed sag a while
		say(s.t, "OP DES with the speedbrake out: worst %.1f kt below the target speed (not a check)" % -dip_kt)
	_speedbrake(s)
	if managed:
		_configure(s)
	if s.vert_fma.begins_with("G/S"):
		_go("glideslope", s)
	elif s.vert_fma.begins_with("ALT\n") and s.alt_ft - s.path_ft > 150.0:
		check(s.t, managed, "levelled at the FCU altitude %.0f ft above the glide slope (expected only in the trap)" % (s.alt_ft - s.path_ft))
		_go("recover", s)


## 3b. Above the beam and level: ALT knob above the aircraft (no ALT capture), V/S -1500 pulled; G/S captures through the beam.
func _recover(s: Dictionary, dt: float) -> void:
	if once("do"):
		Props.set_v("controls/fcu/alt_ft", ceilf((s.alt_ft + 500.0) / 1000.0) * 1000.0)
		Props.set_v("controls/fcu/vs_fpm", RECOVER_VS_FPM)
		knob("fcu_vs_pull")
		say(s.t, "ALT knob to %.0f (above), V/S %.0f pulled" % [Props.get_f("controls/fcu/alt_ft"), RECOVER_VS_FPM])
		return
	if dt > 3.0 and once("check"):
		check(s.t, s.vert_fma == "V/S\nG/S", "FMA V/S with G/S armed and no ALT armed, got %s" % s.fma.replace("\n", " "))
	_speedbrake(s)
	_configure(s)
	if s.vert_fma.begins_with("G/S"):
		_go("glideslope", s)


## 4. G/S captured (from above): ALT knob to the go-around altitude, SPD pushed (managed: green dot, then each flap speed); gear
## down, flaps as the speed allows, speedbrake while fast; autobrake MED.
func _glideslope(s: Dictionary, dt: float) -> void:
	if once("do"):
		check(s.t, s.vert_fma.begins_with("G/S"), "G/S captured %.1f nm out at %.0f ft, %.0f kt" % [s.dest_nm, s.alt_ft, s.ias])
		Props.set_v("controls/fcu/alt_ft", INTERCEPT_FT)
		knob("fcu_spd_push")
		say(s.t, "ALT knob to %.0f (go-around altitude), SPD pushed (managed)" % INTERCEPT_FT)
	_speedbrake(s)
	_configure(s)
	if s.ra < 2000.0:
		_go("final", s)


## Speedbrake by the height above the 3 degree path (full over 1,500 ft high, half over 500 ft) and to lose speed (more than
## 15 kt fast); in with flaps FULL and below 1,000 ft, as the A320 wants.
func _speedbrake(s: Dictionary) -> void:
	var high: float = s.alt_ft - s.path_ft
	var want := 1.0 if high > 1500.0 else (0.5 if high > 500.0 else 0.0)
	if s.ias > s.spd_tgt_kt + 15.0 and s.ra > 1500.0:
		want = maxf(want, 0.5 if s.ias < s.spd_tgt_kt + 25.0 else 1.0)
	if _flaps >= 5 or s.ra < 1000.0:
		want = 0.0
	if want != _sb:
		_sb = want
		Props.set_v("controls/speedbrake", want)
		say(s.t, "speedbrake %s (%.0f ft above the path, %.0f kt for %.0f)" % ["in" if want == 0.0 else ("half" if want < 1.0 else "full"),
			high, s.ias, s.spd_tgt_kt])


func _configure(s: Dictionary) -> void:
	if _gear == 0 and (s.vert_fma.begins_with("G/S") or _flaps >= 2 or s.ra < 2500.0) and s.ias < 250.0:
		_gear = 1
		Props.set_v("controls/gear", 1)
		say(s.t, "gear down at %.0f kt, %.0f ft" % [s.ias, s.alt_ft])
	var next := mini(_flaps + 1, 5)
	if next != _flaps and s.ias < VFE[next] - 8.0 and (next <= 3 or _gear == 1):
		_flaps = next
		Props.set_v("controls/flaps", next)
		say(s.t, "flaps %d at %.0f kt (target %.0f), %.0f ft" % [next, s.ias, s.spd_tgt_kt, s.alt_ft])


## 5. Below 2,000 ft: stabilised by 1,000 ft (gear down, CONF 3 or FULL, LOC and G/S, CAT3 DUAL, at the approach speed).
func _final(s: Dictionary) -> void:
	_speedbrake(s)
	_configure(s)
	if s.ra < 1000.0:
		check(s.t, _gear == 1 and _flaps >= 4 and int(Props.get_v("controls/autobrake", 0)) == 2,
			"gear down, CONF 3 or FULL and autobrake MED at 1,000 ft (flaps %d)" % _flaps)
		check(s.t, s.vert_fma == "G/S" and s.lat_fma == "LOC", "on LOC and G/S at 1,000 ft, got %s" % s.fma)
		check(s.t, s.appr_fma.find("CAT3") >= 0, "CAT3 DUAL at 1,000 ft, got %s" % s.appr_fma)
		check(s.t, absf(s.ias - s.spd_tgt_kt) < 10.0 and s.spd_tgt_kt < 150.0, "at the approach speed: %.0f kt for %.0f" % [s.ias, s.spd_tgt_kt])
		check(s.t, absf(s.dev_ft) < 75.0 and absf(s.cross) < 30.0, "on the path: %.0f ft off the glide path, %.0f m off the centreline" % [s.dev_ft, s.cross])
		check(s.t, s.vs > -1100.0 and Props.get_f("controls/speedbrake") == 0.0, "sink rate %.0f ft/min, speedbrake in" % s.vs)
		_go("land", s)


## 6. LAND at 400 ft, FLARE, RETARD (levers to idle), touchdown, ROLL OUT.
func _land(s: Dictionary) -> void:
	if s.thr_fma == "RETARD" and Props.get_f("controls/throttle_1") > 0.0:
		for k in LEVERS:
			Props.set_v(k, 0.0)
		say(s.t, "RETARD: levers to idle at %.0f ft RA" % s.ra)
	if s.wow:
		for w in ["LAND", "FLARE"]:
			check(s.t, _seen.has(w), "%s was shown" % w)
		_go("rollout", s)
