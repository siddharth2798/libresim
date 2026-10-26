class_name ApproachLights
extends RefCounted
## Approach lighting systems (pure layout):
## - precision (ILS) ends: ALSF-II / CALVERT-like 900 m centreline of 5-light white
##   barrettes every 30 m, crossbars at 150 m and 300 m, red side-row barrettes over the
##   inner 270 m, and sequenced flashers ("the rabbit") from 900 m in to 330 m, 2 Hz.
## - other ends of runways >= 1200 m: simple 420 m system (3-light barrettes every 60 m,
##   crossbar at 300 m). Shorter runways get none.
## Fixtures stand LIFT above the ground under them. (They used to be held at threshold height
## or above, which left them floating up to 20 m in the air where the approach ground falls
## away, e.g. VAPO; no pole is drawn, so a floating light has nothing to stand on.)

const LIFT := 0.6
const FULL_LEN := 900.0
const SIMPLE_LEN := 420.0
const FLASH_IN := 330.0  # flashers from FULL_LEN down to here
const FLASH_SPAN := 0.6  # fraction of the 0.5 s cycle the sequence takes


## Approach lights of end i of runway r: steady lights into s, flashers into flash.
static func build(r: Dictionary, i: int, hf: Callable, s: LightSet, flash: LightSet) -> void:
	if r.ils[i]:
		precision(r, i, hf, s, flash)
	elif r.len >= 1200.0:
		simple(r, i, hf, s)


static func _h(hf: Callable, p: Vector2) -> float:
	return hf.call(p.x, p.y) + LIFT


## Flash phase (0..1 of the cycle) of a flasher dist metres out: the farthest fires first.
static func flash_phase(dist: float) -> float:
	return (FULL_LEN - dist) / (FULL_LEN - FLASH_IN) * FLASH_SPAN


static func precision(r: Dictionary, i: int, hf: Callable, s: LightSet, flash: LightSet) -> void:
	var f := RunwayLightLayout.end_frame(r, i)
	var t: Vector2 = f[0]
	var o: Vector2 = -f[1]  # outward, along the approach
	var side := Vector2(o.y, -o.x)
	var W := RunwayLightLayout.WHITE
	var dist := 30.0
	while dist <= FULL_LEN + 1.0:
		var c := t + o * dist
		for k in range(-2, 3):  # centreline barrette
			var p: Vector2 = c + side * k * 1.05
			s.add(p.x, p.y, _h(hf, p), W, o, 3.0, 0.04, false, 0.0, 1.1)
		if dist <= 270.0:  # red side-row barrettes, in line with the touchdown zone
			for sg in [-1.0, 1.0]:
				for k in 3:
					var p2: Vector2 = c + side * sg * (9.0 + k * 1.5)
					s.add(p2.x, p2.y, _h(hf, p2), RunwayLightLayout.RED, o, 3.0, 0.04, false, 0.0, 1.0)
		if is_equal_approx(dist, 150.0) or is_equal_approx(dist, 300.0):
			var reach := 7.5 if dist < 200.0 else 15.0
			for sg in [-1.0, 1.0]:
				var w := 3.0 if dist < 200.0 else 4.5
				while w <= reach + 0.1:
					var p3: Vector2 = c + side * sg * w
					s.add(p3.x, p3.y, _h(hf, p3), W, o, 3.0, 0.04, false, 0.0, 1.1)
					w += 1.5
		if dist >= FLASH_IN - 1.0:
			var p4: Vector2 = c - o * 2.0
			flash.add(p4.x, p4.y, _h(hf, p4) + 0.4, Color(0.85, 0.9, 1.0), o, 2.0, 0.05, false,
				1.0 + flash_phase(dist), 1.6)
		dist += 30.0


static func simple(r: Dictionary, i: int, hf: Callable, s: LightSet) -> void:
	var f := RunwayLightLayout.end_frame(r, i)
	var t: Vector2 = f[0]
	var o: Vector2 = -f[1]
	var side := Vector2(o.y, -o.x)
	var W := RunwayLightLayout.WHITE
	var dist := 60.0
	while dist <= SIMPLE_LEN + 1.0:
		var c := t + o * dist
		for k in range(-1, 2):
			var p: Vector2 = c + side * k * 1.0
			s.add(p.x, p.y, _h(hf, p), W, o, 3.0, 0.05, false, 0.0, 1.0)
		if is_equal_approx(dist, 300.0):
			for sg in [-1.0, 1.0]:
				for k in 4:
					var p2: Vector2 = c + side * sg * (4.5 + k * 3.5)
					s.add(p2.x, p2.y, _h(hf, p2), W, o, 3.0, 0.05, false, 0.0, 1.0)
		dist += 60.0
