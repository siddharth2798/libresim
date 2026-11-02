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

## id -> service (see atc_facilities.gd) and the plain-language menu text; {who} is the unit that
## answers ("Ask Ground for taxi"). label_lined: the wording once lined up; blind: at a field without ATC.
const INTENTS := {
	"atis": {"service": "atis", "label": "Listen to ATIS", "label_info": "Ask {who} for airport information", "blind": ""},
	"clearance": {"service": "clearance", "label": "Ask {who} for clearance", "blind": ""},
	"pushback": {"service": "ground", "label": "Ask {who} for pushback", "blind": "Blind call: start-up and pushback"},
	"taxi": {"service": "ground", "label": "Ask {who} for taxi", "blind": "Blind call: taxi"},
	"ready": {"service": "tower", "label": "Report ready for departure", "label_lined": "Ask {who} for takeoff clearance",
		"blind": "Blind call: ready for departure"},
	"inbound": {"service": "approach", "label": "Ask {who} for landing", "blind": "Blind call: inbound for landing"},
	"final": {"service": "tower", "label": "Report final", "blind": "Blind call: final"},
	"goaround": {"service": "tower", "label": "Report going around", "blind": "Blind call: going around"},
	"taxi_stand": {"service": "ground", "label": "Ask {who} for taxi to parking", "blind": "Blind call: taxi to parking"},
}

## Airline profile (aircraft.json atc.profile): the same calls and states, worded for an IFR flight; no
## circuit ("report final" becomes "report established", landing = approach clearance).
const AIRLINE_LABELS := {
	"clearance": {"label": "Ask {who} for IFR clearance", "blind": ""},
	"ready": {"label": "Report ready for departure", "label_lined": "Report ready for takeoff", "blind": "Blind call: ready for departure"},
	"inbound": {"label": "Ask {who} for the approach", "blind": "Blind call: inbound, approach"},
	"final": {"label": "Report established on the approach", "blind": "Blind call: established"},
	"goaround": {"label": "Report going around", "blind": "Blind call: going around"},
	"taxi_stand": {"label": "Ask {who} for taxi to the stand", "blind": "Blind call: taxi to the stand"},
}


## The intent's menu texts for a profile (the airline ones override the base).
static func intent(id: String, profile := "ga") -> Dictionary:
	var d: Dictionary = INTENTS[id].duplicate()
	if AtcProfile.is_airline(profile):
		d.merge(AIRLINE_LABELS.get(id, {}), true)
	return d


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
