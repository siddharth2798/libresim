class_name AirlinerCabin
extends Node
## Bleed air, packs and cabin pressure of an airliner, only as Props for the SD (no faults). Bleed air comes
## from a running engine (N2 >= bleed_n2_min percent) or the APU (apu/running with its bleed on); with a
## source and a pack on, the cabin climbs on a schedule (cabin altitude = field altitude + cabin_ratio x height
## above it, capped at max_cabin_alt_m and, through the pressure difference, at max_dp_pa), at most
## climb_ms up / descent_ms down. On the ground, or without air, the cabin follows the ambient altitude.
## The numbers are the aircraft's aircraft.json "systems.cabin" over DEFAULTS.
## Switches (Props controls/bleed/*, default on): eng1, eng2, apu, pack1, pack2.
## Reads: fdm/alt_m, fdm/wow, atmosphere/pressure_pa, engines/<n>/n2, apu/running.
## Publishes systems/bleed/{eng1_on, eng2_on, apu_on, avail, pressure_pa}, systems/packs/{1_on, 2_on},
##   systems/cabin/{alt_m, delta_p_pa, vs_mps}.

const DEFAULTS := {
	"bleed_n2_min": 50.0, "bleed_pa": 241000.0, "cabin_ratio": 0.2, "max_cabin_alt_m": 2438.0,
	"max_dp_pa": 59300.0, "climb_ms": 2.54, "descent_ms": 1.52, "ambient_ms": 8.0,
}

var def: AircraftDef
var cabin_alt_m := 0.0
var field_m := 0.0  # altitude of the last ground contact
var _p := DEFAULTS.duplicate(true)


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)
	if def == null:
		def = AircraftDef.current()
	_p = def.section_or("cabin", DEFAULTS)
	for k in ["eng1", "eng2", "apu", "pack1", "pack2"]:
		if not Props.has("controls/bleed/" + k):
			Props.set_v("controls/bleed/" + k, true)


func save_key() -> String:
	return "airliner_cabin"


func save_state() -> Dictionary:
	return {"cabin_alt_m": cabin_alt_m, "field_m": field_m}


func load_state(d: Dictionary) -> void:
	cabin_alt_m = float(d.get("cabin_alt_m", cabin_alt_m))
	field_m = float(d.get("field_m", field_m))


## ISA pressure (Pa) at an altitude (m).
static func isa_pa(h: float) -> float:
	return 101325.0 * pow(maxf(1.0 - 2.25577e-5 * h, 0.01), 5.25588)


## ISA altitude (m) of a pressure (Pa).
static func isa_alt(pa: float) -> float:
	return (1.0 - pow(pa / 101325.0, 1.0 / 5.25588)) / 2.25577e-5


func _physics_process(dt: float) -> void:
	var alt := Props.get_f("fdm/alt_m")
	var wow := Props.get_b("fdm/wow", true)
	var amb := Props.get_f("atmosphere/pressure_pa", isa_pa(alt))
	var e1: bool = Props.get_b("controls/bleed/eng1") and Props.get_f("engines/1/n2") >= _p.bleed_n2_min
	var e2: bool = Props.get_b("controls/bleed/eng2") and Props.get_f("engines/2/n2") >= _p.bleed_n2_min
	var apu: bool = Props.get_b("controls/bleed/apu") and Props.get_b("apu/running")
	var avail: bool = e1 or e2 or apu
	var packs: bool = avail and (Props.get_b("controls/bleed/pack1") or Props.get_b("controls/bleed/pack2"))
	if wow:
		field_m = alt
	var target := alt
	var rate: float = _p.ambient_ms
	if packs and not wow:
		target = minf(field_m + maxf(alt - field_m, 0.0) * _p.cabin_ratio, field_m + _p.max_cabin_alt_m)
		target = minf(maxf(target, isa_alt(amb + _p.max_dp_pa)), alt)  # pressure difference limit
		rate = _p.climb_ms if target > cabin_alt_m else _p.descent_ms
	elif packs:
		rate = _p.descent_ms
	var before := cabin_alt_m
	cabin_alt_m = move_toward(cabin_alt_m, target, rate * dt)
	Props.set_v("systems/bleed/eng1_on", e1)
	Props.set_v("systems/bleed/eng2_on", e2)
	Props.set_v("systems/bleed/apu_on", apu)
	Props.set_v("systems/bleed/avail", avail)
	Props.set_v("systems/bleed/pressure_pa", _p.bleed_pa if avail else 0.0)
	Props.set_v("systems/packs/1_on", packs and Props.get_b("controls/bleed/pack1"))
	Props.set_v("systems/packs/2_on", packs and Props.get_b("controls/bleed/pack2"))
	Props.set_v("systems/cabin/alt_m", cabin_alt_m)
	Props.set_v("systems/cabin/delta_p_pa", maxf(isa_pa(cabin_alt_m) - amb, 0.0))
	Props.set_v("systems/cabin/vs_mps", (cabin_alt_m - before) / maxf(dt, 1e-6))
