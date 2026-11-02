class_name TurbineFadec
extends RefCounted
## FADEC thrust limits of a turbofan: config fadec_limits (toga / flex / mct / climb / idle / mrev N1
## tables in percent N1 over altitude, TAT, Mach ...) evaluated with Expr, and the thrust-lever ->
## N1 target mapping. Lever -1 .. 1 with the A320 detents: 0 idle, CL at DETENTS[1], FLX/MCT at [2],
## TOGA at 1 (linear between), reverse idle at -0.1 (the reverser must be deployed: `rev_ready`) up to
## -1 = max reverse (mrev limit). Without fadec_limits the lever is linear from idle to max N1.

const DETENTS := [0.0, 0.556, 0.778, 1.0]
const REV_IDLE := 0.1

var limits := {}  # table name ("toga-table" ...) -> percent N1, last update
var ctx := {}
var _list: Array = []  # [{key, name, f}]
var _idle_pct: float
var _max_pct: float


func _init(fadec_limits: Dictionary, idle_n1: float, max_n1: float) -> void:
	_idle_pct = idle_n1 * 100.0
	_max_pct = max_n1 * 100.0
	for k in fadec_limits:
		var e: Dictionary = fadec_limits[k]
		_list.append({"key": k, "name": e.name, "f": e.f})
	ctx["/systems/fadec/limit/flex-temp-input"] = 0.0


func has_tables() -> bool:
	return not _list.is_empty()


## Evaluate every limit in the current conditions (they may refer to earlier ones: flex uses toga).
func update(mach: float, alt_ft: float, tat_c: float, on_ground: bool, flap_lever: int, flex_c: float) -> void:
	ctx["velocities/mach"] = mach
	ctx["/position/altitude-ft"] = alt_ft
	ctx["propulsion/tat-c"] = tat_c
	ctx["gear/unit[0]/WOW"] = 1.0 if on_ground else 0.0
	ctx["/controls/flight/flaps-input"] = 1.0 if flap_lever >= 2 else 0.0
	ctx["/systems/fadec/limit/flex-temp-input"] = flex_c
	for e in _list:
		var v := Expr.eval(e.f, ctx)
		ctx[e.name] = v
		limits[e.key] = v


func toga_pct() -> float:
	return limits.get("toga-table", _max_pct)


func idle_pct() -> float:
	return maxf(_idle_pct, limits.get("idle-table", 0.0))


## Percent N1 the engine is commanded to for a lever position.
func n1_target(lever: float, flex_set: bool, rev_ready: bool) -> float:
	var idle := idle_pct()
	if not has_tables():
		return idle + clampf(lever, 0.0, 1.0) * (_max_pct - idle)
	if lever < 0.0:
		if not rev_ready:
			return idle
		var x := clampf((-lever - REV_IDLE) / (1.0 - REV_IDLE), 0.0, 1.0)
		return lerpf(idle, maxf(idle, limits.get("mrev-table", idle)), x)
	var cl := maxf(idle, limits.get("climb-table", idle))
	var mid := maxf(cl, limits["flex-table"] if flex_set and limits.has("flex-table") else limits.get("mct-table", cl))
	var top := maxf(mid, toga_pct())
	var v := [idle, cl, mid, top]
	var l := clampf(lever, 0.0, 1.0)
	for i in 3:
		if l <= DETENTS[i + 1]:
			return lerpf(v[i], v[i + 1], (l - DETENTS[i]) / (DETENTS[i + 1] - DETENTS[i]))
	return top
