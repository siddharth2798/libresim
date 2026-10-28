class_name AirlinerLights
extends Node
## Exterior lights of an airliner: each switch (Props controls/lights/<name>) gives a lit light only when its
## bus is powered, and the landing lights extend (landing_extend_s) before they light. The model's lights and
## the FDM read the switches directly (aircraft_lights.gd also uses systems/electrical/powered), so these
## Props are the airliner-correct version for whoever wants the bus-aware state.
## The aircraft's aircraft.json "systems.lights" over DEFAULTS: "bus" ({light: bus name, one of the
## systems/electrical/<bus>_on buses}) and landing_extend_s.
## Reads: controls/lights/{nav, beacon, strobe, taxi, landing, wing, logo, rwy_turnoff}, systems/electrical/<bus>_on.
## Publishes systems/lights/<name>_on for each, systems/lights/landing_<l|r>_pos (0 stowed .. 1 extended: what
## fdm_airliner_props could read for the landing-light drag) and landing_<l|r>_on.

const NAMES := ["nav", "beacon", "strobe", "taxi", "landing", "wing", "logo", "rwy_turnoff"]
const DEFAULTS := {
	"landing_extend_s": 2.5,
	"bus": {"nav": "ac_ess", "beacon": "ac_ess", "strobe": "ac_ess", "taxi": "ac_ess", "landing": "ac_ess",
		"wing": "ac_ess", "logo": "ac_ess", "rwy_turnoff": "ac_ess", "landing_r": "ac_ess"},
}

var def: AircraftDef
var landing_pos := [0.0, 0.0]  # left, right
var _p := DEFAULTS.duplicate(true)


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)
	if def == null:
		def = AircraftDef.current()
	_p = def.section_or("lights", DEFAULTS)


func save_key() -> String:
	return "airliner_lights"


func save_state() -> Dictionary:
	return {"landing_pos": landing_pos.duplicate()}


func load_state(d: Dictionary) -> void:
	var a = d.get("landing_pos", null)
	if a is Array and a.size() >= 2:
		landing_pos = [clampf(float(a[0]), 0.0, 1.0), clampf(float(a[1]), 0.0, 1.0)]


func _powered(light: String) -> bool:
	return Props.get_b("systems/electrical/%s_on" % _p.bus.get(light, "ac_ess"))


func _physics_process(dt: float) -> void:
	var h := "systems/lights/"
	for n in NAMES:
		Props.set_v(h + n + "_on", Props.get_b("controls/lights/" + n) and _powered(n))
	var want := Props.get_b("controls/lights/landing")
	var step: float = dt / maxf(_p.landing_extend_s, 0.01)
	for i in 2:
		var side := "l" if i == 0 else "r"
		var up := want and _powered("landing" if i == 0 else "landing_r")
		landing_pos[i] = move_toward(landing_pos[i], 1.0 if want else 0.0, step) if up or not want else landing_pos[i]
		Props.set_v(h + "landing_%s_pos" % side, landing_pos[i])
		Props.set_v(h + "landing_%s_on" % side, up and landing_pos[i] >= 0.95)
