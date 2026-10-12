class_name CalloutLogic
extends RefCounted
## Training callouts (optional, off by default). The C172 has no automatic callouts, so
## these are what a flight instructor or a "pilot monitoring" would call: Airspeed alive,
## Rotate, Positive rate on takeoff; radio-altitude calls on the approach (500, 100, 50, 30,
## 20, 10); and cautions for sink rate, low airspeed and bank angle near the ground.
## Pure logic, no nodes: step() takes the state dict and the current inputs and returns the
## calls to make now as [[text, level], ...] (level 0 = info, 1 = caution).

const ALIVE_KT := 40.0       # airspeed alive
const ROTATE_KT := 55.0      # Vr
const HEIGHTS := [500, 100, 50, 30, 20, 10]  # ft AGL
const WORDS := {500: "Five hundred", 100: "One hundred", 50: "Fifty", 30: "Thirty", 20: "Twenty", 10: "Ten"}
const COOLDOWN := 4.0        # s between repeats of the same caution


static func new_state() -> Dictionary:
	return {"alive": false, "rotate": false, "positive": false, "fired": {}, "cool": {}}


## i: {ias (kt), agl (ft), vs (fpm), wow (bool), bank (deg), throttle (0..1)}; now in seconds.
static func step(s: Dictionary, i: Dictionary, now: float) -> Array:
	var out := []
	var ias: float = i.ias
	var agl: float = i.agl
	var vs: float = i.vs
	var wow: bool = i.wow
	# --- takeoff ---
	if wow and ias < 25.0:  # parked or taxiing: re-arm for the next takeoff
		s.alive = false
		s.rotate = false
		s.positive = false
	if wow and i.throttle > 0.75:
		if not s.alive and ias >= ALIVE_KT:
			s.alive = true
			out.append(["Airspeed alive", 0])
		if s.alive and not s.rotate and ias >= ROTATE_KT:
			s.rotate = true
			out.append(["Rotate", 0])
	if not wow and s.rotate and not s.positive and vs > 200.0 and agl > 10.0:
		s.positive = true
		out.append(["Positive rate", 0])
	# --- approach heights (each once per approach; only when descending) ---
	if wow or agl > 700.0:
		s.fired = {}
	elif vs < -100.0 and agl < 600.0:
		var lowest := -1
		for h in HEIGHTS:
			if agl <= h and not s.fired.get(h, false):
				s.fired[h] = true
				lowest = h  # HEIGHTS descends, so this ends as the lowest one crossed
		if lowest > 0 and agl >= lowest * 0.5:  # not when spawning far below the call
			out.append([WORDS[lowest], 0])
	# --- cautions near the ground ---
	if not wow:
		if agl < 500.0 and agl > 30.0 and vs < -1000.0:
			_caution(s, out, "Sink rate", now)
		if agl < 400.0 and agl > 15.0 and ias > 20.0 and ias < 54.0:
			_caution(s, out, "Low airspeed", now)
		if agl < 500.0 and absf(float(i.bank)) > 35.0:
			_caution(s, out, "Bank angle", now)
	return out


static func _caution(s: Dictionary, out: Array, text: String, now: float) -> void:
	if now - float(s.cool.get(text, -999.0)) >= COOLDOWN:
		s.cool[text] = now
		out.append([text, 1])
