class_name CabinDoor
extends Node
## The player's cabin door. controls/door_open (key "door_toggle") is the request; systems/door_pos eases 0..1 toward it
## in OPEN_S seconds. A model pivot follows it with the drive "cabin_door" (aircraft/model_drives.gd, a "map" gives the angle).
## The door only opens with the aircraft stopped on the ground: a request while moving or airborne is refused, and an open
## door shuts by itself once the aircraft rolls (pushback, taxi), so it can never hang open in flight.
## A new flight or a restart closes it (ControlActions.RAMP_SEEDS via AircraftControls.restore_defaults).

const OPEN_S := 3.0
const STILL_MPS := 0.5  # ground speed below which the door may open


## Next door position for a request, dt seconds on.
static func step(pos: float, open: bool, dt: float) -> float:
	return move_toward(pos, 1.0 if open else 0.0, dt / OPEN_S)


## May the door be open: on the ground and standing still.
static func allowed() -> bool:
	return Props.get_b("fdm/wow") and Props.get_f("fdm/groundspeed_mps") < STILL_MPS


func _process(dt: float) -> void:
	var p := Props.get_f("systems/door_pos")
	if Props.get_b("controls/door_open") and not allowed():
		Props.set_v("controls/door_open", false)
		_note("Cabin door closed" if p > 0.0 else "Stop on the ground to open the door")
	var n := step(p, Props.get_b("controls/door_open"), dt)
	if n != p:
		Props.set_v("systems/door_pos", n)


func _note(text: String) -> void:
	var notes := get_tree().get_first_node_in_group("notifications") as Notifications if is_inside_tree() else null
	if notes != null:
		notes.post(text, "", Notifications.INFO, "cabin_door")
