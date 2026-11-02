class_name AirlinerNodes
extends RefCounted
## The flight-scene nodes only an airliner (aircraft.json systems.profile "airliner") has, added by
## world/flight.gd after the scene is built: the glass-cockpit instrument publishers (air data with the
## speed markers, ADIRS attitude, per-engine EWD feed, ND route feed) and the autoflight (AP / FD /
## A/THR). The C172 scene stays as it is. The systems (electrical, hydraulics, fuel, lights, ...) are made
## by the AircraftSystems node of the scene (systems/aircraft_systems.gd), which has to be first under Systems.

const AUTOFLIGHT := "res://systems/autoflight.gd"


static func wanted(def: AircraftDef) -> bool:
	return AircraftSystems.profile_of(def) == "airliner"


## `instruments` / `systems` are the scene's Instruments and Systems nodes, `nav_db` the NavDatabase.
static func add(instruments: Node, systems: Node, nav_db: NavDatabase) -> void:
	for pair in [["AirlinerAirData", AirlinerAirData], ["Adirs", Adirs], ["AirlinerEngines", AirlinerEngines]]:
		var n: Node = pair[1].new()
		n.name = pair[0]
		instruments.add_child(n)
	var feed := NdFeed.new()
	feed.name = "NdFeed"
	feed.db = nav_db
	instruments.add_child(feed)
	if ResourceLoader.exists(AUTOFLIGHT):  # loaded by path: a broken autoflight must not stop the C172 scene from parsing
		var af: Node = load(AUTOFLIGHT).new()
		af.name = "Autoflight"
		af.set("db", nav_db)
		systems.add_child(af)


## Pilot controls of a start (flight.gd _reset): levers idle, engine masters on when the engines run (a
## runway or air start) and off for a cold start, which also spools the engines down. The batteries stay
## on (an air start keeps the trimmed thrust, `air`; no battery switch among the controls yet), so the starter and the displays work from the gate.
static func start_state(fdm: FDM, cold: bool, air := false) -> void:
	for i in fdm.units.size():
		var n := i + 1
		if air:  # the trimmed levers of place_airborne stay (controls/throttle only: the per-engine ones follow)
			Props.set_v("controls/throttle_%d" % n, Props.get_f("controls/throttle"))
		else:
			Props.set_v("controls/throttle_%d" % n, 0.0)
		Props.set_v("controls/reverse_%d" % n, 0.0)
		Props.set_v("controls/engine_master_%d" % n, not cold)
		if cold:
			var e = fdm.units[i].engine
			e.set("n1", 0.0)
			e.set("n2", 0.0)
			e.set("running", false)
	for k in ["controls/engine_mode", "controls/autobrake"]:
		Props.set_v(k, 0)
	Props.set_v("controls/speedbrake", 0.0)
	Props.set_v("controls/apu_master", false)
	Props.set_v("controls/apu_start", false)


## A heavy aircraft dropped on the ground sinks by its static spring deflection (0.3 m on the A320 mains) over
## the first second, which looks like a hop at spawn. Let it settle on its springs here and keep it at rest.
static func settle_on_ground(fdm: FDM, seconds := 3.0) -> void:
	for i in int(seconds * 120.0):
		fdm.step(1.0 / 120.0)
	fdm.v_b = Vector3.ZERO
	fdm.w_b = Vector3.ZERO
