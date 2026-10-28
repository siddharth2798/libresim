class_name EngineLevers
extends RefCounted
## Writes the per-engine pilot levers (throttle, mixture) into Props.
## FdmNode reads engine 1 from controls/<name> and engine n >= 2 from controls/<name>_<n> only if
## that prop exists, else from the shared controls/<name>. A writer that set just the shared prop
## after one separate write would leave an engine on a stale value, so the rule here is:
##   * one engine: only controls/<name> (exactly the C172 path);
##   * several engines: ALWAYS write controls/<name> (= engine 1), its mirror controls/<name>_1 and
##     every controls/<name>_<n>, so the fallback never applies;
##   * shared levers (default): a write moves every engine; separate levers (A320 style, throttle
##     only): write(name, i, v) moves engine i alone, write_all still moves all.
## With reverse (controls.levers.throttle reverse / group "reverse") the lever position is
## throttle_n - reverse_n (see lever_detents.gd): reverse_n = controls/reverse_<n> for n >= 1.

const SEPARATE_NAMES := ["throttle"]

var count := 1
var separate := false
var reverse := false
var reverse_frac := 0.0  # share of a joystick lever's travel that is reverse
var detents: Array = []


## spec = aircraft.json controls.levers.throttle ({} when absent); reverse_offered = group "reverse".
static func make(engines: int, spec: Dictionary, reverse_offered := false) -> EngineLevers:
	var l := EngineLevers.new()
	l.count = maxi(engines, 1)
	l.separate = bool(spec.get("separate", false)) and l.count > 1
	l.reverse = bool(spec.get("reverse", reverse_offered)) or reverse_offered
	l.reverse_frac = float(spec.get("reverse_frac", 0.2)) if l.reverse else 0.0
	var d = spec.get("detents", [])
	l.detents = d if d is Array else []
	return l


func _put(name: String, i: int, v: Variant) -> void:
	if i == 0:
		Props.set_v("controls/" + name, v)
		if count > 1:
			Props.set_v("controls/%s_1" % name, v)
	else:
		Props.set_v("controls/%s_%d" % [name, i + 1], v)


## Lever i (0-based) of `name`, with FdmNode's fallback to the shared one.
func read(name: String, i := 0, default := 0.0) -> float:
	if i > 0:
		var own := "controls/%s_%d" % [name, i + 1]
		if Props.has(own):
			return Props.get_f(own)
	return Props.get_f("controls/" + name, default)


## Move lever i (all of them unless the levers are separate).
func write(name: String, i: int, v: float) -> void:
	if count <= 1:
		Props.set_v("controls/" + name, v)
	elif separate and name in SEPARATE_NAMES:
		_put(name, i, v)
	else:
		write_all(name, v)


func write_all(name: String, v: float) -> void:
	if count <= 1:
		Props.set_v("controls/" + name, v)
		return
	for i in count:
		_put(name, i, v)


## Reverse selected on engine i (controls/reverse_<n>), 0..1.
func read_reverse(i := 0) -> float:
	return Props.get_f("controls/reverse_%d" % (i + 1))


## Lever position of engine i: forward 0..1, reverse -1..0.
func pos(i := 0) -> float:
	return read("throttle", i) - (read_reverse(i) if reverse else 0.0)


## Set the position of lever i (all unless separate); outside the travel it is clamped.
func write_pos(i: int, p: float) -> void:
	p = LeverDetents.clamp_pos(p, reverse)
	write("throttle", i, maxf(p, 0.0))
	if not reverse:
		return
	var targets := [i] if separate else range(count)
	for k in targets:
		Props.set_v("controls/reverse_%d" % (k + 1), maxf(-p, 0.0))


func write_pos_all(p: float) -> void:
	for i in (count if separate else 1):
		write_pos(i, p)


## Copy engine 1's levers to the others (a new flight, or after a load).
func sync_all() -> void:
	if count <= 1:
		return
	write_all("throttle", read("throttle", 0))
	if reverse:
		for k in count:
			Props.set_v("controls/reverse_%d" % (k + 1), read_reverse(0))
