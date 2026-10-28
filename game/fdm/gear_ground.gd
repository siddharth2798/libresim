class_name GearGround
extends RefCounted
## Spring-damper ground contacts (JSBSim c172p contact points). BOGEY contacts
## are wheels: rolling friction along the wheel heading (nosewheel steers with
## the rudder pedals), brakes up to static friction, saturated lateral friction.
## STRUCTURE contacts (skids, wingtips) scrape with dynamic friction.
## Works in NED (x north, y east, z down) with Basis r_bn = body -> NED.

const V_SAT_LONG := 0.25  # m/s, friction ramps linearly below this (avoids jitter)
const V_SAT_LAT := 0.12
const DAMP_RAMP := 0.03  # m: damping builds up over the first 3 cm of compression (tyre + leg), so
                         # first contact is not an instant c*v force step
const BRAKE_MU := 0.45  # effective max braking friction, dry asphalt (tyre + anti-skid-free brakes)

## Contact roles (config "role", else derived from the contact): nose / main / tail for wheels
## (tail = a tailwheel behind the mains), wingtip / tail_skid / skid for structure points.
## "brake_group" LEFT / RIGHT / BOTH picks which brake pedal slows a wheel.
var contacts: Array = []  # {name, wheel, role, pos, k, c, mu_s, mu_d, mu_roll, steer, brake}
var steer_cmd := 0.0  # -1..1 (right pedal positive)
var brake_left := 0.0
var brake_right := 0.0
var wow := false  # weight on wheels
var compression := {}  # name -> m
var info := {}  # name -> {depth, vz (NED, + down), force, n, e} for the damage model


func _init(cfg: Dictionary) -> void:
	var main_x := _main_x(cfg)
	for g in cfg.gear:
		var wheel: bool = g.type == "BOGEY"
		contacts.append({
			"name": g.name, "wheel": wheel, "role": str(g.get("role", _role(g, wheel, main_x))),
			"pos": Vector3(g.pos_m[0], g.pos_m[1], g.pos_m[2]),
			"k": g.spring_n_per_m, "c": g.damping_n_s_per_m,
			"mu_s": g.static_friction, "mu_d": g.dynamic_friction, "mu_roll": g.rolling_friction,
			"steer": deg_to_rad(g.max_steer_deg),
			"brake": {"LEFT": 1, "RIGHT": 2, "BOTH": 3}.get(str(g.get("brake_group", "NONE")).to_upper(), 0),
		})


## Mean x (structural, aft positive) of the fixed wheels: the nose / tail split.
static func _main_x(cfg: Dictionary) -> float:
	var sum := 0.0
	var n := 0
	for g in cfg.gear:
		if g.type == "BOGEY" and float(g.max_steer_deg) == 0.0:
			sum += float(g.pos_m[0])
			n += 1
	return sum / n if n > 0 else 0.0


static func _role(g: Dictionary, wheel: bool, main_x: float) -> String:
	if wheel:
		if float(g.max_steer_deg) == 0.0:
			return "main"
		return "nose" if float(g.pos_m[0]) < main_x else "tail"
	var n := str(g.name).to_upper()
	if n.contains("TIP"):
		return "wingtip"
	if n.contains("TAIL"):
		return "tail_skid"
	return "skid"


## Wheels on the steered end (nose or tail) and on the fixed mains, for placing the aircraft.
func steered_wheels() -> Array:
	return contacts.filter(func(c): return c.wheel and c.steer > 0.0)


func main_wheels() -> Array:
	return contacts.filter(func(c): return c.wheel and c.steer == 0.0)


## Returns [force_body, moment_body] about the CG.
## pos_ned: CG position; v_b, w_b: body velocity & rates; ground_h(n, e) -> height (m, up).
func compute(mb: MassBalance, r_bn: Basis, pos_ned: Vector3, v_b: Vector3, w_b: Vector3, ground_h: Callable) -> Array:
	var f_total := Vector3.ZERO
	var m_total := Vector3.ZERO
	var r_nb := r_bn.transposed()
	wow = false
	for c in contacts:
		var r_b := mb.body_of(c.pos)
		var p := pos_ned + r_bn * r_b
		var gd: float = -ground_h.call(p.x, p.y)  # ground "down" coordinate
		var depth := p.z - gd
		if depth <= 0.0:
			compression[c.name] = 0.0
			info[c.name] = {"depth": 0.0}
			continue
		compression[c.name] = depth
		if c.wheel:
			wow = true
		var v_c := r_bn * (v_b + w_b.cross(r_b))  # contact point velocity, NED
		var n := maxf(c.k * depth + c.c * v_c.z * minf(depth / DAMP_RAMP, 1.0), 0.0)
		info[c.name] = {"depth": depth, "vz": v_c.z, "force": n, "n": p.x, "e": p.y}
		# wheel heading in the horizontal plane
		var fwd := r_bn * Vector3(1, 0, 0)
		if c.wheel and c.steer > 0.0:
			fwd = r_bn * Vector3(cos(c.steer * steer_cmd), sin(c.steer * steer_cmd), 0.0)
		var f_h := Vector2(fwd.x, fwd.y).normalized()
		var s_h := Vector2(-f_h.y, f_h.x)
		var v_long := v_c.x * f_h.x + v_c.y * f_h.y
		var v_lat := v_c.x * s_h.x + v_c.y * s_h.y
		info[c.name]["vlat"] = v_lat  # sideways drift of the tyre (side load)
		var mu_long: float = c.mu_roll
		var mu_lat: float = lerpf(c.mu_s, c.mu_d, clampf(absf(v_lat) / 2.0, 0.0, 1.0))
		if c.wheel:
			var b := 0.0
			match c.brake:
				1: b = brake_left
				2: b = brake_right
				3: b = maxf(brake_left, brake_right)
			mu_long = lerpf(c.mu_roll, BRAKE_MU, b)
		else:
			mu_long = c.mu_d
			mu_lat = c.mu_d
		var fl := -clampf(v_long / V_SAT_LONG, -1.0, 1.0) * mu_long * n
		var fs := -clampf(v_lat / V_SAT_LAT, -1.0, 1.0) * mu_lat * n
		var f_ned := Vector3(f_h.x * fl + s_h.x * fs, f_h.y * fl + s_h.y * fs, -n)
		var f_b := r_nb * f_ned
		f_total += f_b
		m_total += r_b.cross(f_b)
	return [f_total, m_total]
