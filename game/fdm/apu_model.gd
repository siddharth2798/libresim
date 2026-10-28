class_name ApuModel
extends RefCounted
## Auxiliary power unit reduced to a spool (config top-level "apu": thrust_n and tsfc_kg_per_n_s only
## scale the fuel flow). Master on + a start press latches a start: N goes 0 -> 100 % in START_S, the
## unit is "available" (bleed / electrical source flag) from AVAIL_N. Master off or no fuel: it runs down
## in COAST_S. No bleed, no EGT, no failures yet (the systems phase builds on this).
## state: n (0..1), starting, running (above AVAIL_N), ff_kgs.

const START_S := 30.0
const COAST_S := 20.0
const AVAIL_N := 0.95

var n := 0.0
var starting := false
var running := false
var ff_kgs := 0.0
var _flow_at_full := 0.0


func _init(cfg: Dictionary) -> void:
	_flow_at_full = float(cfg.get("thrust_n", 1000.0)) * float(cfg.get("tsfc_kg_per_n_s", 1.4e-5))


func update(dt: float, master: bool, start: bool, fuel_ok: bool) -> void:
	if start and master:
		starting = true
	if not master or not fuel_ok:
		starting = false
	if starting or (running and master and fuel_ok):
		n = move_toward(n, 1.0, dt / START_S)
	else:
		n = move_toward(n, 0.0, dt / COAST_S)
	running = n >= AVAIL_N if not running else n >= AVAIL_N - 0.1
	if running:
		starting = false
	ff_kgs = _flow_at_full * n if (starting or running) and fuel_ok and master else 0.0
