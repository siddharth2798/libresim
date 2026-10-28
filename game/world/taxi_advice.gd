class_name TaxiAdvice
extends RefCounted
## "Slow down" advice while taxiing (ui/taxi_banner.gd): when the ground speed exceeds the aircraft's
## ground.max_taxi_kt a short note is due, then not again until the speed has dropped
## below 90 % of the limit and COOLDOWN s have passed. No limit key (max_taxi_kt <= 0, the C172) = never.

const COOLDOWN := 30.0

var _wait := 0.0
var _armed := true


## Advance by dt. Returns the note to show ("" for none).
func tick(dt: float, groundspeed_mps: float, max_kt: float) -> String:
	_wait = maxf(_wait - dt, 0.0)
	if max_kt <= 0.0:
		return ""
	var kt := Units.mps_to_kt(groundspeed_mps)
	if kt < max_kt * 0.9:
		_armed = true
	if kt > max_kt and _armed and _wait <= 0.0:
		_armed = false
		_wait = COOLDOWN
		return "Taxi speed %d kt — keep it under %d kt" % [roundi(kt), roundi(max_kt)]
	return ""
