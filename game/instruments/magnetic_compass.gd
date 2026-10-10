class_name MagneticCompass
extends Node
## Pendulous magnetic compass. The card hangs along the apparent vertical
## (specific force), so in turns and accelerations it reads the Earth's field
## projected onto a tilted plane -> real northerly-turning and acceleration
## errors. Card motion is a damped 2nd-order system (overshoot / swing).
## Local field near Mumbai/Pune (WMM ~2025): declination ~ -0.3 deg, dip ~ +26 deg.

const DECLINATION := deg_to_rad(-0.3)
const DIP := deg_to_rad(26.0)
const WN := 2.5   # rad/s card natural frequency
const ZETA := 0.45

var fdm: FDM
var _card := 0.0  # rad, magnetic heading shown
var _rate := 0.0


func _physics_process(dt: float) -> void:
	if fdm == null:
		return
	var r_bn := Basis(fdm.q)
	var sf := r_bn * fdm.accel_b
	var up := sf.normalized() if sf.length() > 1.0 else Vector3(0, 0, -1)  # NED "up" seen by the float
	# Earth field (NED): north-ish horizontal + downward dip component
	var b := Vector3(cos(DIP) * cos(DECLINATION), cos(DIP) * sin(DECLINATION), sin(DIP))
	var b_plane := b - up * b.dot(up)  # field in the card plane
	var nose := r_bn * Vector3(1, 0, 0)
	var nose_plane := nose - up * nose.dot(up)
	var right_plane := up.cross(nose_plane)  # NED: up x fwd = left... use sign below
	var x := b_plane.dot(nose_plane)
	var y := -b_plane.dot(right_plane)
	var target := -atan2(y, x)  # heading of the nose relative to magnetic north
	var err := wrapf(target - _card, -PI, PI)
	_rate += (WN * WN * err - 2.0 * ZETA * WN * _rate) * dt
	_card = wrapf(_card + _rate * dt, 0.0, TAU)
	Props.set_v("instruments/compass_deg", fposmod(rad_to_deg(_card), 360.0))


func settle() -> void:
	if fdm:
		_card = fposmod(fdm.euler().z - DECLINATION, TAU)
		_rate = 0.0
