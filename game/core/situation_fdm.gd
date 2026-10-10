class_name SituationFdm
extends RefCounted
## FDM state <-> JSON-safe Dictionary for saved flight situations (core/situation.gd).
## Covers everything FDM.step() carries from one step to the next: rigid-body state,
## filter memories, engine / propeller / flaps / fuel / mass state, aero stall
## hysteresis and the damage model (incl. collapsed gear legs), so a restored FDM
## continues exactly like the original. Vectors are stored as float arrays and the
## file is written with full precision, so the round trip is bit-exact.

const ENGINE_KEYS := ["throttle", "mixture", "magnetos", "starter", "fuel_ok", "failed", "partial",
	"running", "map_pa", "fuel_flow_kgs", "power_w", "egt_k", "cht_k", "oil_temp_k", "oil_press_pa", "torque"]
const PROP_KEYS := ["rpm", "thrust", "torque", "v_induced", "advance_ratio"]
const FCS_KEYS := ["pitch", "roll", "yaw", "pitch_trim", "flap_cmd", "flaps_powered", "flap_motor_running",
	"elevator", "aileron", "rudder", "flap_deg"]
const FDM_KEYS := ["pos_n", "pos_e", "pos_d", "feed_left", "feed_right", "fuel_available", "leak_left_kgs",
	"leak_right_kgs", "time", "alpha", "beta", "vt", "cas", "qbar", "mach", "agl", "load_factor",
	"flight_load_factor", "_alpha_prev", "_alphadot"]
const DAMAGE_KEYS := ["crash_reason", "prop_destroyed", "flaps_jammed", "structure_damaged", "hard_landings",
	"_overspeed_t", "_flap_t", "_air_time"]
## Fields that are ints in the scripts (JSON turns every number into a float).
const INTS := ["magnetos", "flap_cmd", "hard_landings"]


static func capture(f: FDM) -> Dictionary:
	var d := {}
	for k in FDM_KEYS:
		d[k] = f.get(k)
	d.v_b = vec(f.v_b)
	d.w_b = vec(f.w_b)
	d.q = [f.q.x, f.q.y, f.q.z, f.q.w]
	d.wind_ned = vec(f.wind_ned)
	d.accel_b = vec(f.accel_b)
	d.qnh_pa = f.atmo.qnh_pa
	d.delta_t = f.atmo.delta_t
	d.stall_hyst = f.aero.stall_hyst
	d.engine = _pick(f.engine, ENGINE_KEYS)
	d.prop = _pick(f.prop, PROP_KEYS)
	d.fcs = _pick(f.fcs, FCS_KEYS)
	d.gear = {"steer_cmd": f.gear.steer_cmd, "brake_left": f.gear.brake_left,
		"brake_right": f.gear.brake_right, "wow": f.gear.wow}
	var mb := f.mb
	d.mb = {"tanks": mb.tanks.map(func(t): return t.contents_kg),
		"payload": mb.point_masses.map(func(p): return [p.name, p.kg]),
		# mass/CG/inertia exactly as the FDM last computed them (it refreshes them only
		# every 120 steps), so a restored FDM integrates identically
		"mass": mb.mass, "cg": vec(mb.cg), "inertia": basis(mb.inertia)}
	var dm := f.damage
	d.damage = _pick(dm, DAMAGE_KEYS)
	d.damage.events = Array(dm.events)
	d.damage.gear_failed = dm.gear_failed.keys()
	d.damage.last_touchdown = dm.last_touchdown.duplicate()
	d.damage.was_touching = dm._was_touching.duplicate()
	return d


static func apply(f: FDM, d: Dictionary) -> void:
	for k in FDM_KEYS:
		if d.has(k):
			f.set(k, d[k])
	f.v_b = to_vec(d.v_b)
	f.w_b = to_vec(d.w_b)
	f.q = Quaternion(d.q[0], d.q[1], d.q[2], d.q[3]).normalized()
	f.wind_ned = to_vec(d.wind_ned)
	f.accel_b = to_vec(d.get("accel_b", [0.0, 0.0, -FDM.G]))
	f.atmo.qnh_pa = d.get("qnh_pa", f.atmo.qnh_pa)
	f.atmo.delta_t = d.get("delta_t", f.atmo.delta_t)
	f.aero.stall_hyst = d.get("stall_hyst", 0.0)
	_put(f.engine, d.engine)
	_put(f.prop, d.prop)
	_put(f.fcs, d.fcs)
	# damage: start from a repaired aircraft, then re-break what was broken
	f.damage.reset()
	f.gear = GearGround.new(f.cfg)
	for k in d.gear:
		f.gear.set(k, d.gear[k])
	var dd: Dictionary = d.damage
	for c in f.gear.contacts:
		if c.name in dd.get("gear_failed", []):
			f.damage._fail_gear(c, "")  # same geometry change as the original collapse
	_put(f.damage, dd)
	f.damage.events.assign(dd.get("events", []))
	f.damage.last_touchdown = dd.get("last_touchdown", {}).duplicate()
	f.damage._was_touching = dd.get("was_touching", {}).duplicate()
	# mass & balance
	var mb := f.mb
	var tanks: Array = d.mb.tanks
	for i in mini(tanks.size(), mb.tanks.size()):
		mb.tanks[i].contents_kg = float(tanks[i])
	for p in d.mb.payload:
		for pm in mb.point_masses:
			if pm.name == p[0]:
				pm.kg = float(p[1])
	mb.update()
	if d.mb.has("inertia"):
		mb.mass = d.mb.mass
		mb.cg = to_vec(d.mb.cg)
		mb.inertia = to_basis(d.mb.inertia)
		mb.inertia_inv = mb.inertia.inverse()


static func _pick(o: Object, keys: Array) -> Dictionary:
	var out := {}
	for k in keys:
		out[k] = o.get(k)
	return out


static func _put(o: Object, d: Dictionary) -> void:
	for k in d:
		if not k in o:
			continue
		var v = d[k]
		if k in INTS:
			v = int(v)
		elif typeof(o.get(k)) == TYPE_FLOAT:
			v = float(v)
		elif typeof(v) in [TYPE_DICTIONARY, TYPE_ARRAY]:
			continue  # handled by the caller
		o.set(k, v)


static func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func to_vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func basis(b: Basis) -> Array:
	return vec(b.x) + vec(b.y) + vec(b.z)


static func to_basis(a: Array) -> Basis:
	return Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
