class_name EngineTurbine
extends Powerplant
## Turbofan / turbojet reduced to what a flight sim needs: a spool (N1) that follows the thrust lever
## with different time constants up and down, thrust from N1 with altitude (density) and Mach lapse,
## fuel flow from thrust (TSFC), windmilling drag when it is out, and a simple start (starter spools
## it up, it lights above LIGHT_N1 when fuel is available). No fan / core split and no FADEC curves;
## fits one data point (sea-level static thrust, TSFC) per engine from config.json.
## Config ("type": "turbine"): thrust_n (sea-level static), max_rpm (N1 at 100 %, display only),
## idle_n1, spool_up_s, spool_down_s, tsfc_kg_per_n_s, alt_exponent, mach_lapse, windmill_drag_n,
## start_n1 (what the starter alone reaches), pos_m.

const LIGHT_N1 := 0.18  # fraction of max N1 above which fuel lights
const R_AIR := 287.053
const RHO0 := 1.225

var thrust_sl: float
var idle_n1: float
var spool_up_s: float
var spool_down_s: float
var tsfc: float
var alt_exponent: float
var mach_lapse: float
var windmill_drag: float
var start_n1: float
var n1 := 0.0  # 0..1
var thrust_n := 0.0  # N, negative = windmilling drag


func _init(cfg: Dictionary) -> void:
	thrust_sl = cfg.thrust_n
	max_rpm = cfg.get("max_rpm", 100.0)
	idle_n1 = cfg.get("idle_n1", 0.22)
	idle_rpm = idle_n1 * max_rpm
	spool_up_s = cfg.get("spool_up_s", 5.0)
	spool_down_s = cfg.get("spool_down_s", 3.0)
	tsfc = cfg.get("tsfc_kg_per_n_s", 1.6e-5)
	alt_exponent = cfg.get("alt_exponent", 0.8)
	mach_lapse = cfg.get("mach_lapse", 0.3)
	windmill_drag = cfg.get("windmill_drag_n", 0.003 * thrust_sl)
	start_n1 = cfg.get("start_n1", 0.25)
	max_power = thrust_sl * 250.0  # W at about 250 m/s: scale for gauges only


func warm_start(fraction: float) -> void:
	n1 = fraction
	running = true


func extra_state_keys() -> Array:
	return ["n1", "thrust_n"]


func update(dt: float, _rpm: float, p_amb: float, t_amb: float, airspeed: float) -> void:
	var rho := p_amb / (R_AIR * t_amb)
	var mach := airspeed / sqrt(1.4 * R_AIR * t_amb)
	var can_burn := fuel_ok and not failed
	if running and not can_burn:
		running = false
	elif not running and can_burn and n1 >= LIGHT_N1 and (starter or n1 >= idle_n1 * 0.8):
		running = true  # light-off: the starter has spooled it up, fuel is available
	var wind := clampf(airspeed / 120.0, 0.0, 1.0) * 0.12  # N1 it windmills at
	var target := wind
	if running:
		target = idle_n1 + (1.0 - idle_n1) * clampf(throttle, 0.0, 1.0)
	elif starter:
		target = maxf(start_n1, wind)
	var tau := spool_up_s if target > n1 else spool_down_s
	n1 = clampf(n1 + (target - n1) * minf(dt / tau, 1.0), 0.0, 1.05)
	var lapse := pow(rho / RHO0, alt_exponent) * clampf(1.0 - mach_lapse * mach, 0.3, 1.0)
	if running:
		var x := clampf((n1 - idle_n1) / (1.0 - idle_n1), 0.0, 1.05)
		thrust_n = thrust_sl * lapse * (0.04 + 0.96 * pow(x, 1.4))
		fuel_flow_kgs = tsfc * thrust_n
	else:
		thrust_n = -windmill_drag * clampf(airspeed / 100.0, 0.0, 1.0) * minf(n1 / 0.1, 1.0)
		fuel_flow_kgs = 0.0
	power_w = maxf(thrust_n, 0.0) * airspeed
	torque = 0.0
	var egt_target := t_amb + (600.0 * n1 if running else 0.0)
	egt_k = lerpf(egt_k, egt_target, clampf(dt * 0.5, 0.0, 1.0))
	cht_k = egt_k
	oil_temp_k = lerpf(oil_temp_k, t_amb + 60.0 * n1, clampf(dt * 0.01, 0.0, 1.0))
	oil_press_pa = lerpf(oil_press_pa, clampf(n1 / 0.3, 0.0, 1.0) * 4.0e5, clampf(dt * 2.0, 0.0, 1.0))
	map_pa = p_amb
