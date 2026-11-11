class_name PushbackChecks
extends RefCounted
## What must be true before a pushback starts (world/ground_ops.gd), as the message the pilot sees; "" = go.
## Stopped on the ground, parking brake off, the jet bridge retracted (systems/jetway_attached, world/jetway_rig.gd: key
## jetway_toggle) and every door shut (world/cabin_door.gd: keys passenger_doors_all, cargo_doors_all). `keys` = key bindings for the hints (default: saved).

const STILL_MPS := 0.5


static func blocker(wow: bool, ground_speed: float, keys := {}) -> String:
	if not wow or ground_speed > STILL_MPS:
		return "Pushback is only possible when stopped on the ground"
	if Props.get_b("controls/parking_brake"):
		return "Release the parking brake (Shift+B) for pushback"
	if Props.get_b("systems/jetway_attached"):
		return "Retract the jet bridge (%s) before pushback" % KeyBindings.key_text("jetway_toggle", keys)
	if CabinDoor.any_open("passenger"):
		return "Close the passenger doors (%s) before pushback" % KeyBindings.key_text("passenger_doors_all", keys)
	if CabinDoor.any_open("cargo"):
		return "Close the cargo doors (%s) before pushback" % KeyBindings.key_text("cargo_doors_all", keys)
	return ""


## Once airborne a bridge retracted for pushback may dock again at the arrival gate.
static func after_takeoff(wow: bool) -> void:
	if not wow and Props.get_b("controls/ground/jetway_stowed"):
		Props.set_v("controls/ground/jetway_stowed", false)
