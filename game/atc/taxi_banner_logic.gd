class_name TaxiBannerLogic
extends RefCounted
## When the on-screen taxi / pushback instruction (ui/taxi_banner.gd) stays and when it goes, as pure
## logic (time is passed in). An instruction stays 8-12 s (12 s for the first one after landing, 6 s
## for a plain note such as "No taxi route found"), then fades by itself. It goes sooner when it is
## dismissed (Backspace), when a newer one replaces it (show() restarts it), when the route ends
## (arrived or cleared with T), or when the aircraft starts taxiing under it: it stood still when
## the instruction appeared and has moved for MOVE_HOLD s at over MOVE_SPEED m/s, after the
## instruction had MIN_SHOWN s to be read. One that appears while the aircraft is still rolling out
## after landing only follows the clock.

const MIN_LIFE := 8.0
const MAX_LIFE := 12.0
const FIRST_LIFE := 12.0
const NOTE_LIFE := 6.0
const MIN_SHOWN := 4.0
const MOVE_SPEED := 1.5
const MOVE_HOLD := 2.0
const STILL_SPEED := 1.0

var text := ""
var left := 0.0
var is_route := false  # an instruction of the taxi route (a plain note is not)
var _still := false
var _shown := 0.0
var _moving := 0.0


## How long an instruction stays: 6 s for a note, 12 s the first time after landing, else 8-12 s by length.
static func life_for(txt: String, first_after_landing: bool, note: bool) -> float:
	if note:
		return NOTE_LIFE
	if first_after_landing:
		return FIRST_LIFE
	return clampf(7.0 + float(txt.length()) * 0.04, MIN_LIFE, MAX_LIFE)


## Show (or replace) the message. `still` = the aircraft stands still now.
func show(txt: String, life: float, still: bool, route: bool) -> void:
	text = txt
	left = life
	is_route = route
	_still = still
	_shown = 0.0
	_moving = 0.0


func alive() -> bool:
	return left > 0.0 and text != ""


## Dismiss now (key, arrival, route cleared).
func dismiss() -> void:
	left = 0.0
	text = ""


## Advance by dt with the ground speed (m/s). Returns "" while it stays, "expired" when its time ran
## out, "moving" when it was dismissed because the aircraft started taxiing.
func tick(dt: float, speed_mps: float) -> String:
	if not alive():
		return ""
	left -= dt
	_shown += dt
	if speed_mps > MOVE_SPEED:
		_moving += dt
	else:
		_moving = 0.0
	if left <= 0.0:
		dismiss()
		return "expired"
	if _still and _shown >= MIN_SHOWN and _moving >= MOVE_HOLD:
		dismiss()
		return "moving"
	return ""


## True when a runway-bound route is within `within` m of its hold point and has not said so yet.
static func hold_short_due(rem_m: float, hold_at_end: bool, said: bool, within := 40.0) -> bool:
	return hold_at_end and not said and rem_m < within
