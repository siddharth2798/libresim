class_name FailureManager
extends Node
## Arms the failures chosen in the flight setup (Session.setup.failures) and the random
## failures (Session.setup.random), and trips them when their trigger is met:
## at start, after N minutes of flight time, climbing through N ft AGL, or above N kt IAS.
## Random failures pick systems from the chosen categories and a time uniformly inside
## the window; the pilot is not told what is armed (as in real-world training).
## Out: Props "failures/<id>" flags, "failures/event" (last message) + "failures/event_t".

var fdm_node: FdmNode
var armed: Array = []  # [{id, mode, value, random}]
var elapsed := 0.0  # flight time since start / reset (s), stops while paused
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## (Re)arm everything from the session setup; called at start and on reset (F5).
func restart() -> void:
	FailureCatalog.clear_all()
	elapsed = 0.0
	armed.clear()
	Props.set_v("failures/event", "")
	var s: Dictionary = Session.setup
	for id in s.failures:
		var f: Array = s.failures[id]
		if int(f[0]) > 0:
			armed.append({"id": id, "mode": int(f[0]), "value": float(f[1]), "random": false})
	var r: Dictionary = s.random
	if r.enabled:
		var pool: Array = FailureCatalog.ids_in(r.categories).filter(
			func(id): return not s.failures.has(id) or int(s.failures[id][0]) == 0)
		var lo := float(r.from_min)
		var hi := maxf(float(r.to_min), lo)
		for i in mini(int(r.count), pool.size()):
			var id: String = pool.pop_at(_rng.randi_range(0, pool.size() - 1))
			armed.append({"id": id, "mode": 2, "value": _rng.randf_range(lo, hi), "random": true})
	_check()  # "at start" failures trip before the first frame


func random_pending() -> int:
	return armed.filter(func(a): return a.random).size()


func fail_now(id: String) -> void:
	_trip({"id": id, "random": false}, false)


func repair(id: String) -> void:
	Props.set_v("failures/" + id, false)


func _physics_process(dt: float) -> void:
	if fdm_node == null or fdm_node.paused or fdm_node.fdm.damage.crashed:
		return
	elapsed += dt
	_check()


func _check() -> void:
	if armed.is_empty():
		return
	var agl := Units.m_to_ft(Props.get_f("fdm/agl_m"))
	var ias := Units.mps_to_kt(Props.get_f("fdm/cas_mps"))
	var airborne := not Props.get_b("fdm/wow", true)
	for a in armed.duplicate():
		var go := false
		match a.mode:
			1: go = true
			2: go = elapsed >= a.value * 60.0
			3: go = airborne and agl >= a.value
			4: go = ias >= a.value
		if go:
			armed.erase(a)
			_trip(a, bool(Session.setup.notify))


func _trip(a: Dictionary, notify: bool) -> void:
	Props.set_v("failures/" + a.id, true)
	if notify:
		Props.set_v("failures/event", "FAILURE: " + FailureCatalog.label(a.id))
		Props.set_v("failures/event_t", Time.get_ticks_msec())
