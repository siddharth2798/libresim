class_name EngineTurbineFadec
extends EngineTurbine
## Turbofan with JSBSim-derived tables (config engines[i] with thrust_table; A320 CFM56-5B4) instead of
## EngineTurbine's single-point fit:
##   lever (throttle - reverse, -1..1) --TurbineFadec--> N1 target %; N1 follows it through the spool
##   rate tables (n1_spool_up/down_rate_table, % N1 per s vs N1); N2 follows N1 (idle_n2 at idle N1,
##   rated_n2 at the TOGA limit).
##   thrust = idle + mil * f^2 with idle = thrust_n * idle_thrust_table(mach, density altitude),
##   mil = (thrust_n - idle) * thrust_table(mach, density altitude) * reverser_loss_table(deploy) and
##   f = (N1 - idle N1) / (TOGA limit N1 - idle N1): thrust_n is the flat-rated TOGA thrust, so the
##   limit tables decide the N1 at which it is reached. JSBSim's own N2norm^2 form is the same shape; the
##   normalisation to the FADEC limit instead of max N2 is ours (not checked against JSBSim).
##   fuel flow = tsfc * |thrust| * sqrt(T / 288.15) (* tsfc_table(mach, density altitude) if given).
## Start: the starter (engine_mode IGN/START with the master on, or CRANK) spools N2 at
## jsbsim.n2startrate; above LIGHT_N2 with fuel it lights and accelerates to idle N2 by itself; the
## starter cuts out at CUTOUT_N2. Reverse: only on the ground, the reverser takes REVERSER_S to deploy
## and N1 goes to the reverse target once it is deployed; the thrust is -x. Not running: windmill drag.
## Config keys read: thrust_n idle_n1 max_n1 idle_n2 max_n2 rated_n2 tsfc_kg_per_n_s tsfc_table
## thrust_table idle_thrust_table reverser_loss_table n1_spool_up_rate_table n1_spool_down_rate_table
## fadec_limits (merged in by PowerUnit) jsbsim{n2startrate} windmill_drag_n.

const LIGHT_N2 := 0.22
const CUTOUT_N2 := 0.50
const CRANK_N2 := 0.26  # what the starter alone reaches
const ACCEL_N2 := 0.016  # N2 per s after light-off, up to idle
const DECAY_TAU := 20.0  # s, N2 run-down
const REVERSER_S := 1.5
const EGT_IDLE := 673.0  # K (400 C)
const EGT_TOGA := 1143.0  # K (870 C)

var n2 := 0.0  # 0..1.05
var lever := 0.0  # -1 .. 1
var reverse := 0.0  # 0..1 reverse selected (controls/reverse_<n>)
var master := true
var fire := false
var flex_temp_c := 0.0  # > 0: the FLX/MCT detent uses the flex limit
var flap_lever := 0
var reverser_pos := 0.0  # 0 stowed .. 1 deployed
var fadec: TurbineFadec
var max_n1 := 1.04
var idle_n2 := 0.594
var rated_n2 := 0.98
var crank_rate := 0.0113  # N2 per s
var _cfg: Dictionary
var _env := {}  # table context
var _target_pct := 0.0  # N1 the FADEC commands (percent)


func _init(cfg: Dictionary) -> void:
	super(cfg)
	_cfg = cfg
	max_n1 = cfg.get("max_n1", 1.04)
	idle_n2 = cfg.get("idle_n2", 0.594)
	rated_n2 = cfg.get("rated_n2", minf(0.98, cfg.get("max_n2", 1.05)))
	crank_rate = cfg.get("jsbsim", {}).get("n2startrate", 1.13) / 100.0
	windmill_drag = cfg.get("windmill_drag_n", 0.006 * thrust_sl)
	fadec = TurbineFadec.new(cfg.get("fadec_limits", {}), idle_n1, max_n1)


func extra_state_keys() -> Array:
	return ["n1", "thrust_n", "n2", "reverser_pos", "master", "lever"]


## Running at idle (fraction <= 0.5) or at a cruise-like N1; Trim.snap then settles it.
func warm_start(fraction: float) -> void:
	running = true
	n1 = idle_n1 if fraction <= 0.5 else clampf(fraction * 0.8, idle_n1, 0.9)
	n2 = _n2_of_n1(n1)


func _n2_of_n1(x: float) -> float:
	var span := maxf(fadec.toga_pct() / 100.0 - idle_n1, 0.05)
	return idle_n2 + (rated_n2 - idle_n2) * clampf((x - idle_n1) / span, 0.0, 1.1)


## Jump to the steady state of the current lever (trim): spool, N2 and thrust settle at once.
func snap(p_amb: float, t_amb: float, airspeed: float) -> void:
	update(0.0, 0.0, p_amb, t_amb, airspeed)
	if running:
		n1 = _target_pct / 100.0
		n2 = _n2_of_n1(n1)
	update(0.0, 0.0, p_amb, t_amb, airspeed)


func update(dt: float, _rpm: float, p_amb: float, t_amb: float, airspeed: float) -> void:
	var mach := airspeed / sqrt(1.4 * R_AIR * t_amb)
	var da_ft := AtmosphereISA.density_altitude(p_amb / (R_AIR * t_amb)) / 0.3048
	var tat_c := t_amb * (1.0 + 0.2 * mach * mach) - 273.15
	lever = clampf(throttle - reverse, -1.0, 1.0)
	_env["velocities/mach"] = mach
	_env["atmosphere/density-altitude"] = da_ft
	fadec.update(mach, AtmosphereISA.pressure_altitude(p_amb) / 0.3048, tat_c, on_ground, flap_lever, flex_temp_c)
	_spin(dt, mach)
	var f := 0.0
	var t := 0.0
	if running:
		var span := maxf(fadec.toga_pct() / 100.0 - idle_n1, 0.05)
		f = clampf((n1 - idle_n1) / span, 0.0, 1.04)
		var idle_t: float = thrust_sl * Table.lookup(_cfg.idle_thrust_table, _env)
		var loss: float = Table.eval2(_cfg.reverser_loss_table, reverser_pos) if _cfg.has("reverser_loss_table") else 1.0
		var mil: float = (thrust_sl - idle_t) * Table.lookup(_cfg.thrust_table, _env) * loss
		var spooled := clampf(n2 / idle_n2, 0.0, 1.0)
		t = idle_t * spooled * spooled + mil * f * f
		thrust_n = t * (1.0 - 2.0 * reverser_pos)
		var k: float = Table.lookup(_cfg.tsfc_table, _env) if _cfg.has("tsfc_table") else 1.0
		fuel_flow_kgs = tsfc * k * t * sqrt(t_amb / 288.15)
	else:
		thrust_n = -windmill_drag * clampf(airspeed / 100.0, 0.0, 1.0) * clampf(n2 / 0.15, 0.0, 1.0)
		fuel_flow_kgs = 0.0
	power_w = maxf(thrust_n, 0.0) * airspeed
	torque = 0.0
	_temperatures(dt, t_amb, f)


## Start, run-up, run-down and spool: n1 / n2 / running / reverser for this step.
func _spin(dt: float, mach: float) -> void:
	var can_burn := fuel_ok and not failed and not fire and master
	var starter_on := starter and n2 < CUTOUT_N2 and not failed
	if running and not can_burn:
		running = false
	elif not running and can_burn and starter_on and n2 >= LIGHT_N2:
		running = true
	var want_rev := running and on_ground and lever < -0.05
	reverser_pos = move_toward(reverser_pos, 1.0 if want_rev else 0.0, dt / REVERSER_S)
	if running:
		if n2 < idle_n2 - 1e-4:  # light-off to idle
			n2 = minf(n2 + ACCEL_N2 * dt, idle_n2)
			n1 = idle_n1 * pow(n2 / idle_n2, 2.5)
		else:
			_target_pct = clampf(fadec.n1_target(lever, flex_temp_c > 0.0, reverser_pos >= 0.95), 0.0, max_n1 * 100.0)
			var pct := n1 * 100.0
			var up: bool = _target_pct > pct
			var rate := Table.eval2(_cfg.n1_spool_up_rate_table if up else _cfg.n1_spool_down_rate_table, pct)
			n1 = move_toward(pct, _target_pct, rate * dt) / 100.0
			n2 = _n2_of_n1(n1)
	else:
		var tgt := 0.3 * clampf(mach / 0.6, 0.0, 1.0)  # windmilling
		if starter_on:
			tgt = maxf(tgt, CRANK_N2)
		if tgt > n2:
			n2 = move_toward(n2, tgt, (crank_rate if starter_on else 0.01) * dt)
		else:
			n2 += (tgt - n2) * (1.0 - exp(-dt / DECAY_TAU))
		n1 = idle_n1 * pow(clampf(n2 / idle_n2, 0.0, 1.5), 2.5)


func _temperatures(dt: float, t_amb: float, f: float) -> void:
	var egt_target := t_amb
	if running:
		egt_target = EGT_IDLE + (EGT_TOGA - EGT_IDLE) * f + 120.0 * clampf(1.0 - n2 / idle_n2, 0.0, 1.0)
	var tau := 4.0 if egt_target > egt_k else 25.0
	egt_k = lerpf(egt_k, egt_target, clampf(dt / tau, 0.0, 1.0))
	cht_k = egt_k
	oil_temp_k = lerpf(oil_temp_k, t_amb + 60.0 * minf(n2 / idle_n2, 1.0), clampf(dt * 0.01, 0.0, 1.0))
	oil_press_pa = lerpf(oil_press_pa, clampf(n2 / 0.5, 0.0, 1.0) * 4.0e5, clampf(dt * 2.0, 0.0, 1.0))
	map_pa = 101325.0
