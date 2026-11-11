extends Node
## Every door of an aircraft (aircraft.json ground.doors, world/cabin_door.gd, aircraft/common/cabin_door_panel.gd): one control
## per door and an "all doors" control under Ground operations, doors that only open standing still, pushback that waits for the
## jet bridge and the doors (world/pushback_checks.gd), and the door motions (Airbus plug doors forward, cargo doors up).

const EACH := ["door_r1_toggle", "door_l2_toggle", "door_r2_toggle", "door_cargo_fwd_toggle", "door_cargo_aft_toggle"]


func _reset() -> void:
	for id in CabinDoor.IDS:
		Props.set_v(CabinDoor.req_prop(id), false)
		Props.set_v(CabinDoor.pos_prop(id), 0.0)
	Props.set_v("systems/jetway_attached", false)
	Props.set_v("controls/parking_brake", false)


## A door node for the A320 (the current aircraft while it is made), on the ground and standing still.
func _door_node() -> CabinDoor:
	var prev = Session.setup.get("aircraft", "c172")
	Session.setup.aircraft = "a320"
	var n := CabinDoor.new()
	add_child(n)  # _ready reads the current aircraft's doors
	Session.setup.aircraft = prev
	Props.set_v("fdm/wow", true)
	Props.set_v("fdm/groundspeed_mps", 0.0)
	return n


func test_doors_each_has_its_own_control_on_the_a320_only() -> String:
	var a := AircraftControls.for_def(AircraftDef.load_def("a320"))
	var c := AircraftControls.default_set()
	var labels := {}
	for k in ["door_toggle", "passenger_doors_all", "cargo_doors_all"] + EACH:
		if not k in a.press_keys() or not k in a.buttons() or not k in ControlActions.GROUND:
			return "A320: %s must be a key and a button under Ground operations" % k
		var l := str(KeyBindings.LABELS.get(k, ""))
		if l == "" or labels.has(l):
			return "%s needs its own label (%s)" % [k, l]
		labels[l] = true
	for k in ["passenger_doors_all", "cargo_doors_all"] + EACH:
		if k in c.press_keys():
			return "the C172 has one door: %s must not be listed" % k
	var d := KeyBindings.defaults()
	if d.door_toggle.is_empty() or d.passenger_doors_all.is_empty() or d.cargo_doors_all.is_empty() \
			or not KeyBindings.conflicts(d).is_empty():
		return "O (door L1), Shift+O (passenger doors) and Ctrl+O (cargo doors) by default, without conflicts"
	if "move to / away" in str(KeyBindings.LABELS.jetway_toggle) or not "retract" in str(KeyBindings.LABELS.jetway_toggle).to_lower():
		return "the jet bridge control must say it retracts the bridge: %s" % KeyBindings.LABELS.jetway_toggle
	return ""


func test_doors_a320_lists_its_passenger_and_cargo_doors() -> String:
	var ids := CabinDoor.doors(AircraftDef.load_def("a320")).map(func(s): return str(s.id))
	if ids != ["L1", "R1", "L2", "R2", "CF", "CA"]:
		return "A320 doors %s" % [ids]
	var c172 := CabinDoor.doors(AircraftDef.load_def("c172")).map(func(s): return str(s.id))
	if c172 != ["L1"]:
		return "without a door list the aircraft keeps its one L1 door (%s)" % [c172]
	if CabinDoor.req_prop("L1") != "controls/door_open" or CabinDoor.pos_prop("R2") != "systems/doors/R2":
		return "L1 keeps controls/door_open; the others use controls/doors/<id>"
	return ""


func _bump(kind: String) -> void:
	var k: String = CabinDoor.ALL_REQ[kind]
	Props.set_v(k, int(Props.get_v(k, 0)) + 1)


func _open_ids() -> Array:
	return CabinDoor.IDS.filter(func(id): return Props.get_f(CabinDoor.pos_prop(id)) >= 1.0)


## Passenger and cargo doors are worked apart: "all passenger doors" leaves the cargo doors shut and the other way round;
## a second press shuts them; one door alone; rolling shuts everything.
func test_doors_passenger_and_cargo_open_apart() -> String:
	_reset()
	var n := _door_node()
	var msg := ""
	n._process(0.0)  # sees the counters
	_bump("passenger")
	for i in 16:
		n._process(0.25)
	if _open_ids() != ["L1", "R1", "L2", "R2"]:
		msg = "all passenger doors: open %s (cargo doors must stay shut)" % [_open_ids()]
	_bump("cargo")
	for i in 30:
		n._process(0.25)
	if msg == "" and _open_ids() != CabinDoor.IDS:
		msg = "then all cargo doors: open %s" % [_open_ids()]
	_bump("passenger")
	for i in 16:
		n._process(0.25)
	if msg == "" and (CabinDoor.any_open("passenger") or _open_ids() != ["CF", "CA"]):
		msg = "passenger doors pressed again: they shut, the cargo doors stay open (%s)" % [_open_ids()]
	_bump("cargo")
	for i in 30:
		n._process(0.25)
	if msg == "" and CabinDoor.any_open():
		msg = "cargo doors pressed again: every door shut"
	Props.set_v("controls/doors/R2", true)  # one door alone
	for i in 16:
		n._process(0.25)
	if msg == "" and _open_ids() != ["R2"]:
		msg = "door R2 alone: open %s" % [_open_ids()]
	Props.set_v("fdm/groundspeed_mps", 3.0)  # rolling: it shuts itself
	for i in 16:
		n._process(0.25)
	if msg == "" and CabinDoor.any_open():
		msg = "a door must shut once the aircraft rolls"
	n.queue_free()
	_reset()
	return msg


func test_pushback_waits_for_the_jet_bridge_and_the_doors() -> String:
	_reset()
	var keys := KeyBindings.defaults()
	if PushbackChecks.blocker(true, 0.0, keys) != "":
		return "nothing in the way: pushback may start (%s)" % PushbackChecks.blocker(true, 0.0, keys)
	if not "stopped" in PushbackChecks.blocker(true, 2.0, keys):
		return "moving: pushback must wait"
	Props.set_v("systems/jetway_attached", true)
	var b := PushbackChecks.blocker(true, 0.0, keys)
	Props.set_v("systems/jetway_attached", false)
	if not ("jet bridge" in b and "Shift+J" in b):
		return "bridge on the aircraft: '%s' must name the jet bridge and its key" % b
	Props.set_v("systems/doors/L2", 0.4)
	b = PushbackChecks.blocker(true, 0.0, keys)
	_reset()
	if not ("passenger doors" in b and "Shift+O" in b):
		return "a passenger door open: '%s' must ask to close the passenger doors with their key" % b
	Props.set_v("systems/doors/CA", 0.4)
	b = PushbackChecks.blocker(true, 0.0, keys)
	_reset()
	if not ("cargo doors" in b and "Ctrl+O" in b):
		return "a cargo door open: '%s' must ask to close the cargo doors with their key" % b
	Props.set_v("controls/ground/jetway_stowed", true)
	PushbackChecks.after_takeoff(false)
	if Props.get_b("controls/ground/jetway_stowed"):
		return "airborne, the stowed bridge request must clear (the arrival gate's bridge docks)"
	return ""


## R1 swings out to the right and forward like L1; a cargo door turns up round its top edge, its bottom swinging out.
func test_door_panels_right_side_and_cargo_move_the_right_way() -> String:
	var g: Dictionary = AircraftDef.load_def("a320").section("ground")
	var s := func(p: Vector3): return Vector3(p.y, p.z, p.x + 2.5)  # structural -> local (x right, y up, z aft)
	var panels := CabinDoorPanel.make_all(g, Vector3(-2.5, 0.0, 0.0), s)
	var by := {}
	for d in panels:
		by[d.id] = d
	var msg := "" if by.keys() == ["L1", "R1", "L2", "R2", "CF", "CA"] else "panels %s" % [by.keys()]
	if msg == "":
		var r1: CabinDoorPanel = by.R1
		var p0: Vector3 = r1._hinge.position
		r1._apply(0.575)
		if r1._hinge.position.x - p0.x < 0.4:
			msg = "R1 must swing out to the right (%.2f m)" % (r1._hinge.position.x - p0.x)
		r1._apply(1.0)
		if msg == "" and r1._hinge.position.z - p0.z > -0.9:
			msg = "R1 must end forward of its doorway (%.2f m)" % (r1._hinge.position.z - p0.z)
	if msg == "":
		var cf: CabinDoorPanel = by.CF
		var bottom := Vector3(0.0, -float(g.doors[4].h_m), 0.0)  # a point below the top hinge
		cf._apply(1.0)
		var moved: Vector3 = cf._hinge.basis * bottom
		if not (moved.x > 0.5 and moved.y > 0.0):
			msg = "the forward cargo door's bottom edge must swing out (right) and up: %s" % moved
		if msg == "" and not cf._hinge.visible:
			msg = "open, the cargo door shows"
	for d in panels:
		d.free()
	return msg
