class_name FlightControls
extends RefCounted
## Pilot inputs (normalised) -> control surface positions, JSBSim c172p FCS.
## Pilot conventions: pitch +1 = yoke full aft (nose up), roll +1 = right,
## yaw +1 = right pedal, trim like pitch. Flaps: detent index 0..3, electric travel.
## JSBSim surface signs: +elevator = trailing edge down (nose down),
## +aileron = right roll, +rudder = nose LEFT, hence the sign flips below.

var _surf: Dictionary
var _flap_detents: Array = []  # deg
var _flap_rates: Array = []  # deg/s between detents
var pitch := 0.0
var roll := 0.0
var yaw := 0.0
var pitch_trim := 0.0
var flap_cmd := 0  # detent index
var aileron_rigging := 0.0  # fixed trim tab (config)
var rudder_rigging := 0.0

var elevator := 0.0  # rad
var aileron := 0.0
var rudder := 0.0
var flap_deg := 0.0


func _init(cfg: Dictionary) -> void:
	_surf = cfg.controls.surfaces
	aileron_rigging = cfg.controls.get("aileron_rigging", 0.0)
	rudder_rigging = cfg.controls.get("rudder_rigging", 0.0)
	var prev := 0.0
	for s in cfg.controls.flaps:
		_flap_detents.append(s.deg)
		_flap_rates.append((s.deg - prev) / s.time_s if s.time_s > 0.0 else 1e3)
		prev = s.deg


static func _scale(x: float, r: Dictionary) -> float:
	return deg_to_rad(x * r.max_deg if x >= 0.0 else -x * r.min_deg)


func update(dt: float) -> void:
	var e := clampf(-(pitch + pitch_trim), -1.0, 1.0)
	elevator = _scale(e, _surf.elevator)
	aileron = _scale(clampf(roll + aileron_rigging, -1.0, 1.0), _surf["left-aileron"])
	rudder = _scale(clampf(-(yaw + rudder_rigging), -1.0, 1.0), _surf.rudder)
	var target: float = _flap_detents[clampi(flap_cmd, 0, _flap_detents.size() - 1)]
	if not is_equal_approx(flap_deg, target):
		var seg := 1
		while seg < _flap_detents.size() - 1 and flap_deg >= _flap_detents[seg]:
			seg += 1
		var rate: float = _flap_rates[seg]
		flap_deg = move_toward(flap_deg, target, rate * dt)


func flap_detents() -> int:
	return _flap_detents.size()
