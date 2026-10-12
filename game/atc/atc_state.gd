class_name AtcState
extends RefCounted
## ATC state names and the pilot's calls ("intents"): which service answers each call and
## which calls make sense in which state. The menu shows only those.
##
## States (published as /atc/state):
##   ground:  parked -> clearance -> taxi -> hold_short -> lined_up -> takeoff
##   air:     departed -> enroute -> inbound -> final
##   landing: landed -> vacated -> (taxi ->) parked
## Pilot calls: atis, clearance, pushback, taxi, ready, inbound, final, goaround, taxi_stand.
## "Say again" and "Tune COM1" are added by the controller.

const STATES := ["parked", "clearance", "taxi", "hold_short", "lined_up", "takeoff", "departed",
	"enroute", "inbound", "final", "landed", "vacated"]
const NEAR_RWY := 300.0  # m from a runway: "ready for departure" makes sense

## id -> service (see atc_facilities.gd) and the menu text; {who} is the unit that answers.
const INTENTS := {
	"atis": {"service": "atis", "label": "Listen to ATIS", "label_info": "{who}: request airport information"},
	"clearance": {"service": "clearance", "label": "{who}: request VFR clearance"},
	"pushback": {"service": "ground", "label": "{who}: request start-up and pushback"},
	"taxi": {"service": "ground", "label": "{who}: request taxi"},
	"ready": {"service": "tower", "label": "{who}: ready for departure"},
	"inbound": {"service": "approach", "label": "{who}: inbound, request landing"},
	"final": {"service": "tower", "label": "{who}: report final"},
	"goaround": {"service": "tower", "label": "{who}: going around"},
	"taxi_stand": {"service": "ground", "label": "{who}: runway vacated, request taxi to parking"},
}


## Calls that make sense now, in menu order.
static func available(s: Dictionary, w: Dictionary) -> Array:
	var out := _available(s, w)
	if str(w.get("ctl", "")) == "uncontrolled":  # no ATIS or clearance without a controller: only blind calls
		out = out.filter(func(id): return id != "atis" and id != "clearance")
	return out


static func _available(s: Dictionary, w: Dictionary) -> Array:
	var out := []
	if str(w.get("apt", "")) == "":
		return out
	var st := str(s.get("state", "parked"))
	if bool(w.get("wow", true)):
		var near := float(w.get("rwy_dist", 1e9)) < NEAR_RWY
		match st:
			"parked", "clearance":
				out.append("atis")
				if not bool(s.get("cleared", false)):
					out.append("clearance")
				if bool(w.get("at_stand", false)) and not bool(s.get("pushed", false)):
					out.append("pushback")
				out.append("taxi")
			"taxi":
				out.append("atis")
				if near:
					out.append("ready")
			"hold_short", "lined_up":
				out.append("ready")
				out.append("atis")
			"landed", "vacated":
				out.append("taxi_stand")
	else:
		match st:
			"departed", "enroute":
				out.append("atis")
				out.append("inbound")
			"inbound":
				out.append("final")
				out.append("atis")
			"final":
				out.append("goaround")
			"takeoff":
				pass
	return out


static func service_of(id: String) -> String:
	return str(INTENTS.get(id, {}).get("service", ""))
