class_name CabinDoor
extends Node
## The player's cabin door. controls/door_open (key "door_toggle") is the request; systems/door_pos eases 0..1 toward it
## in OPEN_S seconds. A model pivot follows it with the drive "cabin_door" (aircraft/model_drives.gd, a "map" gives the angle).

const OPEN_S := 3.0


## Next door position for a request, dt seconds on.
static func step(pos: float, open: bool, dt: float) -> float:
	return move_toward(pos, 1.0 if open else 0.0, dt / OPEN_S)


func _process(dt: float) -> void:
	var p := Props.get_f("systems/door_pos")
	var n := step(p, Props.get_b("controls/door_open"), dt)
	if n != p:
		Props.set_v("systems/door_pos", n)
