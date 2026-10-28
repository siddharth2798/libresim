class_name Powerplant
extends RefCounted
## What the FDM and the systems need from an engine, whatever it is: the pilot's levers in,
## engine state out. EnginePiston (with a Propeller) and EngineTurbine (with a TurbineThruster)
## implement it; PowerUnit pairs an engine with its thruster. config.json "type" picks the class
## (PowerUnit.create).

# inputs, set by FdmNode every tick
var throttle := 0.0  # power / thrust lever 0..1
var mixture := 1.0  # piston only
var magnetos := 3  # piston only: bit 1 = L, bit 2 = R
var starter := false
var fuel_ok := true
var failed := false  # catastrophic engine failure
var partial := false  # partial power loss: rough running at ~55 % power
# outputs
var max_power := 1.0  # W (piston: rated shaft power; turbine: equivalent, for display scales)
var max_rpm := 1.0
var idle_rpm := 0.0
var running := false
var map_pa := 101325.0
var fuel_flow_kgs := 0.0
var power_w := 0.0
var egt_k := 288.0
var cht_k := 288.0
var oil_temp_k := 288.0
var oil_press_pa := 0.0
var torque := 0.0  # N*m on the shaft the thruster absorbs (0 for a jet)


## Advance one step. rpm: the thruster's speed (the propeller); pressure (Pa), temperature (K)
## and airspeed (m/s) are the ambient values at the engine.
func update(_dt: float, _rpm: float, _pressure: float, _temperature: float, _airspeed: float) -> void:
	pass


## Put the engine in a running state at this fraction of its max speed (airborne and ground starts).
func warm_start(_fraction: float) -> void:
	pass


## Extra state keys a saved situation must carry for this engine (core/situation_fdm.gd).
func extra_state_keys() -> Array:
	return []
