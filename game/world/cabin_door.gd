class_name CabinDoor
extends Node
## The aircraft's doors (aircraft.json ground.doors; without that list, the one L1 door). Each has a request and a position:
## L1 keeps controls/door_open (key "door_toggle") and systems/door_pos; the others controls/doors/<id> and systems/doors/<id>
## (keys door_r1_toggle ...). The position eases 0..1 toward the request (OPEN_S, CARGO_S for a cargo door). A model pivot can
## follow L1 with the drive "cabin_door" (aircraft/model_drives.gd); CabinDoorPanel draws doors painted on the skin.
## Passenger and cargo doors are worked apart: controls/doors/passenger_all_req (key "passenger_doors_all") and cargo_all_req
## ("cargo_doors_all") are bumped to open every door of that kind, or shut them all when all are already open.
## Doors only open with the aircraft stopped on the ground: a request while moving or airborne is refused, and open doors
## shut by themselves once the aircraft rolls (pushback, taxi), so none can hang open in flight. Pushback waits for them
## (world/ground_ops.gd). A new flight or a restart closes them (ControlActions.RAMP_SEEDS).

const OPEN_S := 3.0
const CARGO_S := 6.0
const STILL_MPS := 0.5  # ground speed below which a door may open
const IDS := ["L1", "R1", "L2", "R2", "CF", "CA"]  # every door a key exists for (ControlActions.TOGGLES)
const CARGO_IDS := ["CF", "CA"]
const ALL_REQ := {"passenger": "controls/doors/passenger_all_req", "cargo": "controls/doors/cargo_all_req"}

var _doors: Array = []  # this aircraft's door specs
var _all_seen := {"passenger": -1, "cargo": -1}


static func req_prop(id: String) -> String:
	return "controls/door_open" if id == "L1" else "controls/doors/" + id


static func pos_prop(id: String) -> String:
	return "systems/door_pos" if id == "L1" else "systems/doors/" + id


## Door specs of an aircraft: ground.doors, or the single L1 door the older keys describe.
static func doors(def: AircraftDef = null) -> Array:
	var d = GroundParams.ground(def).get("doors")
	return d if d is Array and not d.is_empty() else [{"id": "L1", "label": "Cabin door", "kind": "passenger"}]


## Next door position for a request, dt seconds on (`seconds` for the full travel).
static func step(pos: float, open: bool, dt: float, seconds := OPEN_S) -> float:
	return move_toward(pos, 1.0 if open else 0.0, dt / seconds)


## May a door be open: on the ground and standing still.
static func allowed() -> bool:
	return Props.get_b("fdm/wow") and Props.get_f("fdm/groundspeed_mps") < STILL_MPS


## Is any door (of `kind`: "passenger", "cargo", "" = any) open, opening or asked open (pushback waits for them all).
static func any_open(kind := "") -> bool:
	for id in IDS:
		if kind != "" and (id in CARGO_IDS) != (kind == "cargo"):
			continue
		if Props.get_b(req_prop(id)) or Props.get_f(pos_prop(id)) > 0.0:
			return true
	return false


func _ready() -> void:
	_doors = doors(AircraftDef.current())


func _process(dt: float) -> void:
	if _doors.is_empty():  # made without entering the tree
		_doors = doors(AircraftDef.current())
	for kind in ALL_REQ:
		var n: int = Props.get_v(ALL_REQ[kind], 0)
		if n != _all_seen[kind]:
			if _all_seen[kind] >= 0:
				_toggle_all(kind)
			_all_seen[kind] = n
	for id in IDS:
		var spec := _spec(id)
		var rq := req_prop(id)
		if spec.is_empty():
			if Props.get_b(rq):
				Props.set_v(rq, false)
				_note("This aircraft has no door %s" % id)
			continue
		var p := Props.get_f(pos_prop(id))
		if Props.get_b(rq) and not allowed():
			Props.set_v(rq, false)
			_note("%s closed" % str(spec.get("label", "Door")) if p > 0.0 else "Stop on the ground to open the doors")
		var nx := step(p, Props.get_b(rq), dt, CARGO_S if spec.get("kind", "") == "cargo" else OPEN_S)
		if nx != p:
			Props.set_v(pos_prop(id), nx)


func _spec(id: String) -> Dictionary:
	for d in _doors:
		if str(d.get("id", "")) == id:
			return d
	return {}


## Every door of `kind` open, unless all already are (or are opening): then all shut.
func _toggle_all(kind: String) -> void:
	var mine := _doors.filter(func(d): return (str(d.get("kind", "passenger")) == "cargo") == (kind == "cargo"))
	if mine.is_empty():
		_note("This aircraft has no %s doors" % kind)
		return
	var all_open := true
	for d in mine:
		all_open = all_open and Props.get_b(req_prop(str(d.id)))
	if not all_open and not allowed():
		_note("Stop on the ground to open the doors")
		return
	for d in mine:
		Props.set_v(req_prop(str(d.id)), not all_open)
	_note("%s doors %s" % [kind.capitalize(), "closing" if all_open else "opening"])


func _note(text: String) -> void:
	var notes := get_tree().get_first_node_in_group("notifications") as Notifications if is_inside_tree() else null
	if notes != null:
		notes.post(text, "", Notifications.INFO, "cabin_door")
