class_name ModelDrives
extends RefCounted
## What moves a glb pivot (aircraft.json model.surfaces[name].drive), as an angle in radians. Pure
## functions of the FDM, used by AircraftModel._animate_glb. The first group is the C172's; the rest
## is for the A320 (draft in aircraft/a320/model_sections.json):
##   elevator | aileron | rudder        FlightControls field, rad
##   flap_deg | slat_deg | stabilizer_deg   fcs field, degrees
##   spoiler_<l|r><1..n>_deg            one spoiler panel (fcs.spoiler: left panels first, then right)
##   gear_pos | reverser                0..1 unit values: they need a "map"
##   nose_steer_deg                     the steered wheel's angle (tiller + pedals)
##   wheel_nose_rad | wheel_main_l_rad | wheel_main_r_rad   rolling angle (integrated from ground speed)
## "map": [[value, degrees], ...] (piecewise linear, clamped) converts a drive value to degrees, e.g. a
## gear door that opens at 0.1 and shuts at 0.9. "sign" multiplies the result. A reverser pivot belongs to
## engine "engine" (0-based; default: _L -> 0, _R -> 1) and reads Props engines/<n>/reverser.

const NOSE_WHEEL_RADIUS_M := 0.40  # measured on the A320 glb (NLGWheels mesh: 0.80 m tall)
const MAIN_WHEEL_RADIUS_M := 0.57  # MLGWheels mesh: 1.14 m tall
const DEGREE_DRIVES := ["flap_deg", "slat_deg", "stabilizer_deg", "nose_steer_deg"]


## Rotation (rad, before "sign") of the pivot `name` with spec `s`. `wheels` = wheel_angles() state.
static func angle(name: String, s: Dictionary, f: FDM, wheels: Dictionary) -> float:
	var drive := str(s.drive)
	var v := 0.0
	match drive:
		"elevator", "aileron", "rudder":
			v = float(f.fcs.get(drive))
		"flap_deg": v = deg_to_rad(f.fcs.flap_deg)
		"slat_deg": v = deg_to_rad(float(f.fcs.get("slat_deg")))
		"stabilizer_deg": v = deg_to_rad(float(f.fcs.get("stabilizer_deg")))
		"gear_pos": v = float(f.fcs.get("gear_pos")) if "gear_pos" in f.fcs else 1.0
		"reverser": v = Props.get_f("engines/%d/reverser" % (int(s.get("engine", 0 if "_L" in name else 1)) + 1))
		"nose_steer_deg": v = _steer(f)
		_:
			if drive.begins_with("spoiler_"):
				v = deg_to_rad(_spoiler(f, drive))
			elif drive.begins_with("wheel_"):
				v = float(wheels.get(drive, 0.0))
	if s.get("map") is Array:
		return deg_to_rad(table(s.map, v))
	return v


static func table(rows: Array, x: float) -> float:
	if x <= rows[0][0]:
		return float(rows[0][1])
	for i in range(1, rows.size()):
		if x <= rows[i][0]:
			var t: float = (x - rows[i - 1][0]) / maxf(rows[i][0] - rows[i - 1][0], 1e-9)
			return lerpf(float(rows[i - 1][1]), float(rows[i][1]), t)
	return float(rows[-1][1])


## "spoiler_l3_deg" -> degrees of panel 3 of the left wing.
static func _spoiler(f: FDM, drive: String) -> float:
	var sp = f.fcs.get("spoiler")
	if not sp is Array or sp.is_empty() or drive.length() < 12:
		return 0.0
	var k := int(drive.substr(9, 1)) - 1
	var i: int = k + (sp.size() / 2 if drive[8] == "r" else 0)
	return float(sp[i]) if i >= 0 and i < sp.size() else 0.0


static func _steer(f: FDM) -> float:
	var w: Array = f.gear.steered_wheels()
	return rad_to_deg(f.gear._steer_angle(w[0])) if not w.is_empty() and f.gear.has_method("_steer_angle") else 0.0


## Integrates the wheel rolling angles (state: drive name -> rad) from the ground speed while the
## aircraft is on its wheels; in the air the wheels slow down.
static func roll_wheels(wheels: Dictionary, f: FDM, dt: float, radii := {}) -> void:
	var v := Vector2(f.velocity_ned().x, f.velocity_ned().y).length()
	v = 0.0 if v < 0.05 else v  # a parked aircraft creeps by mm/s on its springs: its tyres must not turn
	for k in ["wheel_nose_rad", "wheel_main_l_rad", "wheel_main_r_rad"]:
		var r: float = float(radii.get(k, NOSE_WHEEL_RADIUS_M if k == "wheel_nose_rad" else MAIN_WHEEL_RADIUS_M))
		var rate := v / r if f.gear.wow else float(wheels.get(k + "_rate", 0.0)) * (1.0 - minf(dt * 0.4, 1.0))
		wheels[k + "_rate"] = rate
		wheels[k] = fposmod(float(wheels.get(k, 0.0)) + rate * dt, TAU)
