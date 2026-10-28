class_name AirlinerFixtures
extends RefCounted
## Helpers for tests/test_airliner_systems.gd and test_airliner_fuel.gd: an airliner AircraftDef built in code
## (the A320's config.json, an aircraft.json with systems.profile "airliner"), system nodes made from it, and a
## guard that gives the shared Props tree back as it was.

const DT := 1.0 / 120.0


## The A320 config with an aircraft.json of our own; `systems` is merged into its "systems" section.
static func def(systems := {}, extra := {}) -> AircraftDef:
	var data := {"systems": {"profile": "airliner"}}
	data.systems.merge(systems, true)
	data.merge(extra, true)
	return AircraftDef.make("a320", data, "res://aircraft/a320")


## A system node of class `cls` for `d`, _ready done by hand (no scene tree in the runner).
static func node(cls: GDScript, d: AircraftDef) -> Node:
	var n: Node = cls.new()
	n.set("def", d)
	n._ready()
	return n


## Props the airliner systems read, at neutral values (other suites leave theirs behind).
const NEUTRAL := {
	"engines/1/ff": 0.0, "engines/2/ff": 0.0, "apu/ff_kgs": 0.0, "apu/running": false, "ground/gpu_connected": false,
	"systems/electrical/ac1_on": true, "systems/electrical/ac2_on": true, "systems/electrical/gen1_on": true,
	"systems/electrical/gen2_on": true, "systems/electrical/emer": false, "systems/hydraulics/flaps_ok": true,
	"hyd/low_g": false, "hyd/low_b": false, "hyd/low_y": false, "fuel/low_left": false, "fuel/low_right": false,
	"controls/parking_brake": false, "controls/autobrake": 0, "controls/spoilers_armed": false, "controls/throttle_1": 0.0,
	"controls/throttle_2": 0.0, "controls/speedbrake": 0.0, "controls/engine_master_1": false, "controls/engine_master_2": false,
	"controls/signs/seatbelts": false, "controls/signs/no_smoking": false,
	"fdm/wow": true, "fdm/agl_m": 0.0, "fdm/alt_m": 0.0, "fdm/cas_mps": 0.0, "fdm/mach": 0.0, "fdm/gear_pos": 1.0,
	"fdm/flap_lever": 0.0, "fdm/speedbrake": 0.0, "fdm/stall_warning": false, "fcs/stall_warning": false,
}
const NEUTRAL_OFF := ["gen1", "gen2", "apu_gen", "apu", "battery", "battery_1", "battery_2", "hyd_G", "hyd_B", "hyd_Y",
	"fuel_pump_left", "fuel_pump_centre", "fuel_pump_right", "fuel_leak_left", "fuel_leak_right", "engine_fire", "engine_fire_2"]
const LIGHTS := ["landing", "nav", "beacon", "strobe", "taxi", "wing", "logo", "rwy_turnoff", "panel"]


## Run `f` with the Props tree snapshotted (and set neutral), then restored; returns f's error text.
static func guard(f: Callable) -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	set_all(NEUTRAL)
	for k in NEUTRAL_OFF:
		Props.set_v("failures/" + k, false)
	for k in LIGHTS:
		Props.set_v("controls/lights/" + k, false)
	var err: String = f.call()
	Props._p = snap
	return err


## Physics ticks of every node for `sec` seconds in steps of `dt`.
static func run(nodes: Array, sec: float, dt := DT) -> void:
	for i in int(sec / dt):
		for n in nodes:
			n._physics_process(dt)


## Engines at N2 percent (running above 50), wheels on the ground.
static func engines(n2_1: float, n2_2: float, wow := true) -> void:
	for i in 2:
		var n2 := n2_1 if i == 0 else n2_2
		Props.set_v("engines/%d/n2" % (i + 1), n2)
		Props.set_v("engines/%d/running" % (i + 1), n2 >= 50.0)
	Props.set_v("fdm/wow", wow)


static func set_all(d: Dictionary) -> void:
	for k in d:
		Props.set_v(k, d[k])
