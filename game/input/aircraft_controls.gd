class_name AircraftControls
extends RefCounted
## The pilot controls one aircraft offers: aircraft.json "controls".
##   actions  list of action groups (ControlActions.GROUPS), default = the C172 set
##            (ControlActions.DEFAULT_GROUPS). Actions in no group are offered by every aircraft.
##   levers   {"throttle": {separate: bool (throttle_1 / _2 independent), reverse: bool,
##            reverse_frac: share of a joystick lever's travel that is reverse (default 0.2),
##            detents: [{name, pos, zone}]}}  pos: forward 0..1, reverse -1..0 (lever_detents.gd)
##   defaults {"controls/gear": 1, ...} initial Props, over ControlActions.SEEDS
## Which axis drives which prop is InputBindings.AXES; flap positions come from fdm/flap_detents.
## Actions not offered are hidden from the controls page and help, not dropped from the saved profile.

var id := ""
var groups: Array = []
var engines := 1
var levers: EngineLevers
var defaults := {}
var _offered := {}  # action -> true, for the listed groups


static func for_def(def: AircraftDef) -> AircraftControls:
	var sec := def.section("controls")
	return _build(def.id, sec.get("actions", ControlActions.DEFAULT_GROUPS), def.engine_count(), sec)


static func current() -> AircraftControls:
	return for_def(AircraftDef.current())


## `prev` when it is still the current aircraft's, else rebuilt (cheap per-frame check).
static func refresh(prev: AircraftControls) -> AircraftControls:
	var def := AircraftDef.current()
	return prev if prev != null and prev.id == def.id else for_def(def)


## The C172 set on one engine (no aircraft needed).
static func default_set() -> AircraftControls:
	return _build("", ControlActions.DEFAULT_GROUPS, 1, {})


static func _build(aircraft_id: String, listed, engine_count: int, sec: Dictionary) -> AircraftControls:
	var c := AircraftControls.new()
	c.id = aircraft_id
	c.engines = maxi(engine_count, 1)
	for g in (listed if listed is Array else ControlActions.DEFAULT_GROUPS):
		if ControlActions.GROUPS.has(g):
			c.groups.append(str(g))
			for a in ControlActions.GROUPS[g]:
				c._offered[a] = true
		else:
			push_warning("AircraftControls: unknown action group '%s' in %s" % [g, aircraft_id])
	var lv = sec.get("levers", {})
	c.levers = EngineLevers.make(c.engines, lv.get("throttle", {}) if lv is Dictionary else {}, c.has_group("reverse"))
	var d = sec.get("defaults", {})
	c.defaults = d if d is Dictionary else {}
	return c


func has_group(g: String) -> bool:
	return g in groups


func offers(action: String) -> bool:
	return ControlActions.group_of(action) == "" or _offered.has(action)


func _filter(list: Array) -> Array:
	return list.filter(func(a): return offers(a))


## Offered joystick axes, in InputBindings.AXES order.
func axes() -> Array:
	return _filter(InputBindings.AXES.keys())


func buttons() -> Array:
	return _filter(InputBindings.BUTTONS)


func held_keys() -> Array:
	return _filter(KeyBindings.HELD)


func press_keys() -> Array:
	return _filter(KeyBindings.PRESS)


## Every offered rebindable key action (the controls page rows).
func key_actions() -> Array:
	return held_keys() + press_keys()


## Initial Props of the offered features (never overwrites a prop that exists, e.g. after a load).
func seed_props() -> void:
	var want := {}
	for g in groups:
		want.merge(ControlActions.SEEDS.get(g, {}), true)
	if has_group("engine_master"):
		for n in engines:
			want["controls/engine_master_%d" % (n + 1)] = false
	if levers.reverse:
		for n in engines:
			want["controls/reverse_%d" % (n + 1)] = 0.0
	want.merge(defaults, true)
	for p in want:
		if not Props.has(p):
			Props.set_v(p, want[p])
	levers.sync_all()
