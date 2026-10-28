class_name ReplayChannels
extends RefCounted
## What a replay frame records and how it is played back. Two groups of float32
## channels: FDM state (read directly by the 3-D model, gyros, compass and camera)
## and Props (read by gauges, audio, lights, moving map). Which Props: ReplayLayout
## (the C172 base lists plus the aircraft's aircraft.json "replay" section and the
## per-engine expansion). A prop that did not exist when recorded is stored as NaN
## and left alone on playback.

## FDM state: q (4), v_ned (3), w_b (3), accel_b (3), then scalars, then the extra
## FlightControls fields of the aircraft.
const S_Q := 0
const S_V := 4
const S_W := 7
const S_A := 10
const S_SCALARS := ["elevator", "aileron", "rudder", "flap_deg", "alpha", "beta", "vt", "cas", "agl", "load_factor"]
const S_SC := 13
const N_BASE := 23
## FlightControls fields recorded as state when the aircraft's replay section has "fcs": true and the
## field exists on `fcs` (a scalar, or an Array / packed array: one channel per element). Extend
## this list when FlightControls gets a new animated field.
const EXTRA_FCS_FIELDS := ["slat_deg", "spoiler", "speedbrake", "gear_pos", "thrust_lever"]
## Engine fields (Powerplant) -> prop of engine 1 that older recordings and gauges use.
const LEGACY := {"rpm": "engine/rpm", "running": "engine/running", "egt_k": "engine/egt_k", "cht_k": "engine/cht_k",
	"oil_temp_k": "engine/oil_temp_k", "oil_press_pa": "engine/oil_press_pa"}
const T_FLOAT := 0
const T_BOOL := 1
const T_INT := 2
const T_ENUM := 3

var n_state := N_BASE
var fcs_extra: Array = []  # [field, element index or -1] per extra state channel after the base scalars
var keys: Array[String] = []  # prop keys in channel order (after the state block)
var key_kinds := PackedByteArray()  # T_FLOAT / T_BOOL / T_INT / T_ENUM
var kinds := PackedByteArray()  # buffer interpolation kinds, all channels
var enums := {}  # key -> Array of strings (T_ENUM channels)
var _index := {}  # key -> position in keys
var _elem := {}  # key "base#i" -> [base, i]


## `def` and `fdm` give the aircraft's replay section, engines, tanks and FlightControls fields;
## without them it is the plain C172 layout.
func _init(def: AircraftDef = null, fdm: FDM = null) -> void:
	var n_tanks := fdm.mb.tanks.size() if fdm else 0
	var lay := ReplayLayout.build(def, n_tanks, EXTRA_FCS_FIELDS)
	for field in lay.fcs:
		if fdm == null or not field in fdm.fcs:
			continue
		var v: Variant = fdm.fcs.get(field)
		if v is Array or v is PackedFloat32Array or v is PackedFloat64Array:
			for i in v.size():
				fcs_extra.append([field, i])
		elif typeof(v) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
			fcs_extra.append([field, -1])
	n_state = N_BASE + fcs_extra.size()
	for i in n_state:
		kinds.append(ReplayBuffer.K_LERP)
	kinds[S_Q] = ReplayBuffer.K_QUAT
	for i in 3:
		kinds[S_Q + 1 + i] = ReplayBuffer.K_QUAT_REST
	_add(lay.lerp, ReplayBuffer.K_LERP, T_FLOAT)
	_add(lay.rad, ReplayBuffer.K_ANG_RAD, T_FLOAT)
	_add(lay.deg, ReplayBuffer.K_ANG_DEG, T_FLOAT)
	_add(lay.bool, ReplayBuffer.K_STEP, T_BOOL)
	_add(lay.int, ReplayBuffer.K_STEP, T_INT)
	_add(lay.enums.keys(), ReplayBuffer.K_STEP, T_ENUM)
	enums = lay.enums
	for i in keys.size():
		_index[keys[i]] = i
		if "#" in keys[i]:
			var parts := keys[i].split("#")
			_elem[keys[i]] = [parts[0], int(parts[1])]


func _add(list: Array, kind: int, vtype: int) -> void:
	for k in list:
		keys.append(k)
		key_kinds.append(vtype)
		kinds.append(kind)


func count() -> int:
	return kinds.size()


## Current FDM state + Props as one channel row.
func capture(f: FDM) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	c.resize(kinds.size())
	var q := f.q
	c[S_Q] = q.x; c[S_Q + 1] = q.y; c[S_Q + 2] = q.z; c[S_Q + 3] = q.w
	_put3(c, S_V, f.velocity_ned())
	_put3(c, S_W, f.w_b)
	_put3(c, S_A, f.accel_b)
	var sc := [f.fcs.elevator, f.fcs.aileron, f.fcs.rudder, f.fcs.flap_deg, f.alpha, f.beta, f.vt, f.cas, f.agl, f.load_factor]
	for i in sc.size():
		c[S_SC + i] = sc[i]
	for i in fcs_extra.size():
		c[N_BASE + i] = _fcs_read(f.fcs, fcs_extra[i][0], fcs_extra[i][1])
	for i in keys.size():
		c[n_state + i] = _encode(keys[i], key_kinds[i])
	return c


## Put a recorded frame into the FDM object (position, attitude, rates, surfaces,
## per-engine rpm / running), so everything that reads the FDM directly follows the replay.
func apply_state(fr: Dictionary, f: FDM) -> void:
	var c: PackedFloat32Array = fr.ch
	var p: PackedFloat64Array = fr.pos
	f.pos_e = p[0]
	f.pos_n = p[1]
	f.pos_d = -p[2]
	f.q = Quaternion(c[S_Q], c[S_Q + 1], c[S_Q + 2], c[S_Q + 3]).normalized()
	f.v_b = Basis(f.q).transposed() * _get3(c, S_V)
	f.w_b = _get3(c, S_W)
	f.accel_b = _get3(c, S_A)
	f.fcs.elevator = c[S_SC]
	f.fcs.aileron = c[S_SC + 1]
	f.fcs.rudder = c[S_SC + 2]
	f.fcs.flap_deg = c[S_SC + 3]
	f.alpha = c[S_SC + 4]
	f.beta = c[S_SC + 5]
	f.vt = c[S_SC + 6]
	f.cas = c[S_SC + 7]
	f.agl = c[S_SC + 8]
	f.load_factor = c[S_SC + 9]
	for i in fcs_extra.size():
		_fcs_write(f.fcs, fcs_extra[i][0], fcs_extra[i][1], c[N_BASE + i])
	for i in f.units.size():
		var rpm: Variant = engine_value(c, i, "rpm")
		if rpm != null:
			f.units[i].thruster.rpm = rpm
		var run: Variant = engine_value(c, i, "running")
		if run != null:
			f.units[i].engine.running = run


## Write the recorded Props (plus the vector props derived from the state).
func apply_props(fr: Dictionary) -> void:
	var c: PackedFloat32Array = fr.ch
	var arrays := {}  # base prop -> array being rebuilt from "base#i" channels
	for i in keys.size():
		var x: float = c[n_state + i]
		if is_nan(x):
			continue
		if _elem.has(keys[i]):
			var base: String = _elem[keys[i]][0]
			if not arrays.has(base):
				var cur: Variant = Props.get_v(base)
				arrays[base] = Array(cur) if cur is Array else []
			var a: Array = arrays[base]
			var e: int = _elem[keys[i]][1]
			while a.size() <= e:
				a.append(0.0)
			a[e] = x
			continue
		match key_kinds[i]:
			T_FLOAT: Props.set_v(keys[i], x)
			T_BOOL: Props.set_v(keys[i], x >= 0.5)
			T_INT: Props.set_v(keys[i], int(roundf(x)))
			T_ENUM:
				var list: Array = enums[keys[i]]
				var n := int(roundf(x))
				if n >= 0 and n < list.size():
					Props.set_v(keys[i], list[n])
	for base in arrays:
		Props.set_v(base, arrays[base])
	var p: PackedFloat64Array = fr.pos
	Props.set_v("fdm/position_enu", Vector3(p[0], p[1], p[2]))
	Props.set_v("fdm/body_rates", _get3(c, S_W))
	Props.set_v("fdm/accel_body", _get3(c, S_A))


## A recorded prop's value with its type (null if it was not recorded / absent).
func prop_value(c: PackedFloat32Array, key: String) -> Variant:
	var i: int = _index.get(key, -1)
	if i < 0 or is_nan(c[n_state + i]):
		return null
	var x: float = c[n_state + i]
	match key_kinds[i]:
		T_BOOL: return x >= 0.5
		T_INT: return int(roundf(x))
		T_ENUM:
			var list: Array = enums[key]
			var n := int(roundf(x))
			return list[n] if n >= 0 and n < list.size() else null
	return x


## Recorded value of engine i (0-based): a Powerplant field ("rpm", "running", "egt_k", ...) from
## engines/<n>/<name>, engine 1 also from its legacy engine/* prop; a lever ("throttle", "mixture")
## from controls/<name>_<n>, else controls/<name> (FdmNode's rule). null if not recorded.
func engine_value(c: PackedFloat32Array, i: int, name: String) -> Variant:
	if name in ReplayLayout.ENGINE_LEVERS:
		var own: Variant = prop_value(c, "controls/%s_%d" % [name, i + 1]) if i > 0 else null
		return own if own != null else prop_value(c, "controls/" + name)
	var v: Variant = prop_value(c, "engines/%d/%s" % [i + 1, name])
	if v == null and i == 0 and LEGACY.has(name):
		v = prop_value(c, LEGACY[name])
	return v


## Take control of the aircraft at a replay frame: the levers, engine temperatures and tank
## contents of every unit, trim and flap command (the live Props are written by apply_props).
func apply_resume(c: PackedFloat32Array, f: FDM) -> void:
	var g := func(k: String, d: Variant) -> Variant:
		var v: Variant = prop_value(c, k)
		return d if v == null else v
	f.fcs.pitch_trim = g.call("controls/pitch_trim", f.fcs.pitch_trim)
	f.fcs.flap_cmd = g.call("controls/flaps", f.fcs.flap_cmd)
	for i in f.units.size():
		var e: Powerplant = f.units[i].engine
		for name in ["throttle", "mixture", "egt_k", "cht_k", "oil_temp_k", "oil_press_pa"]:
			var v: Variant = engine_value(c, i, name)
			if v != null and name in e:
				e.set(name, v)
	if _elem.is_empty():  # two tanks: the left / right sums of the C172 channels
		f.mb.set_side_kg("left", g.call("fuel/left_kg", f.mb.side_kg("left")))
		f.mb.set_side_kg("right", g.call("fuel/right_kg", f.mb.side_kg("right")))
	else:
		for i in f.mb.tanks.size():
			f.mb.tanks[i].contents_kg = g.call("fuel/tank_kg#%d" % i, f.mb.tanks[i].contents_kg)
	f.mb.update()


static func velocity_ned(c: PackedFloat32Array) -> Vector3:
	return _get3(c, S_V)


## Exact copy of the FDM fields apply_state() overwrites (to return to live flight).
func save_live(f: FDM) -> Dictionary:
	var extra := []
	for fe in fcs_extra:
		extra.append(_fcs_read(f.fcs, fe[0], fe[1]))
	return {"n": f.pos_n, "e": f.pos_e, "d": f.pos_d, "q": f.q, "v_b": f.v_b, "w_b": f.w_b,
		"accel_b": f.accel_b, "el": f.fcs.elevator, "ail": f.fcs.aileron, "rud": f.fcs.rudder,
		"flap": f.fcs.flap_deg, "alpha": f.alpha, "beta": f.beta, "vt": f.vt, "cas": f.cas,
		"agl": f.agl, "nz": f.load_factor, "extra": extra,
		"rpm": f.units.map(func(u): return u.thruster.rpm), "running": f.units.map(func(u): return u.engine.running)}


func restore_live(f: FDM, s: Dictionary) -> void:
	f.pos_n = s.n; f.pos_e = s.e; f.pos_d = s.d
	f.q = s.q; f.v_b = s.v_b; f.w_b = s.w_b; f.accel_b = s.accel_b
	f.fcs.elevator = s.el; f.fcs.aileron = s.ail; f.fcs.rudder = s.rud; f.fcs.flap_deg = s.flap
	f.alpha = s.alpha; f.beta = s.beta; f.vt = s.vt; f.cas = s.cas; f.agl = s.agl
	f.load_factor = s.nz
	for i in fcs_extra.size():
		_fcs_write(f.fcs, fcs_extra[i][0], fcs_extra[i][1], s.extra[i])
	for i in f.units.size():
		f.units[i].thruster.rpm = s.rpm[i]
		f.units[i].engine.running = s.running[i]


## Channel value of a prop key: NaN when the prop is absent (or an enum string is not in its table).
func _encode(key: String, vtype: int) -> float:
	var v: Variant
	if _elem.has(key):
		var a: Variant = Props.get_v(_elem[key][0])
		var e: int = _elem[key][1]
		v = a[e] if a is Array and e < a.size() else null
	else:
		v = Props.get_v(key)
	if v == null:
		return NAN
	if vtype == T_ENUM:
		var n: int = (enums[key] as Array).find(str(v))
		return NAN if n < 0 else float(n)
	return float(v)


static func _fcs_read(fcs: Object, field: String, idx: int) -> float:
	var v: Variant = fcs.get(field)
	if idx >= 0:
		return float(v[idx]) if (v is Array or v is PackedFloat32Array or v is PackedFloat64Array) and idx < v.size() else NAN
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL] else NAN


static func _fcs_write(fcs: Object, field: String, idx: int, x: float) -> void:
	if is_nan(x):
		return
	var cur: Variant = fcs.get(field)
	if idx >= 0:
		if (cur is Array or cur is PackedFloat32Array or cur is PackedFloat64Array) and idx < cur.size():
			cur[idx] = x  # packed arrays are copies: set the field back
			fcs.set(field, cur)
	elif typeof(cur) == TYPE_INT:
		fcs.set(field, int(roundf(x)))
	elif typeof(cur) == TYPE_BOOL:
		fcs.set(field, x >= 0.5)
	else:
		fcs.set(field, x)


static func _put3(c: PackedFloat32Array, o: int, v: Vector3) -> void:
	c[o] = v.x; c[o + 1] = v.y; c[o + 2] = v.z


static func _get3(c: PackedFloat32Array, o: int) -> Vector3:
	return Vector3(c[o], c[o + 1], c[o + 2])
