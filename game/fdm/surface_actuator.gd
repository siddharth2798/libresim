class_name SurfaceActuator
extends RefCounted
## One control surface (or the stabilizer): first-order lag (bandwidth lag_rad_s) then a rate limit
## (deg/s), output clipped to [lo, hi] degrees. Values are degrees, JSBSim final-deg conventions
## (aileron / elevator positive = trailing edge down, rudder positive = nose right).

var name := ""
var output := ""  # JSBSim property the aero model reads ("/systems/fcs/rudder/final-deg")
var pos := 0.0  # deg
var cmd := 0.0  # deg
var lag := 25.0  # rad/s
var rate := 80.0  # deg/s
var lo := -90.0
var hi := 90.0
var max_deg := 25.0  # full stick


func _init(n: String, spec: Dictionary) -> void:
	name = n
	output = str(spec.get("output", n))
	lag = float(spec.get("lag_rad_s", 25.0))
	rate = float(spec.get("rate_deg_s", 80.0))
	max_deg = float(spec.get("max_deg", 25.0))
	var clip = spec.get("clip_deg")
	lo = float(clip[0]) if clip is Array else -max_deg
	hi = float(clip[1]) if clip is Array else max_deg


func settle() -> void:
	pos = clampf(cmd, lo, hi)


func update(dt: float) -> void:
	var want := (clampf(cmd, lo, hi) - pos) * (1.0 - exp(-lag * dt))
	pos += clampf(want, -rate * dt, rate * dt)
