class_name Adirs
extends Node
## Air data inertial reference system of an airliner: the attitude and heading source of the PFD / ND,
## separate from the C172's vacuum gyros (gyro_instruments.gd) and perfect unless failed.
## In: fdm/{pitch_rad, roll_rad, heading_rad, track_rad, accel_body}; failures/adr or failures/adirs.
## Out: instruments/adirs/{pitch_rad, roll_rad, heading_deg (magnetic), track_deg (magnetic),
## slip (-1..1, + = ball right of centre, 1 = a quarter g sideways), valid}.

const VAR_DEG := -0.3  # magnetic variation near Mumbai, as in avionics/gps.gd
const G := 9.80665


func _physics_process(_dt: float) -> void:
	publish()


## Slip ball from the body-axes specific force (y right): the ball rolls toward the low side.
static func slip_of(accel_body: Vector3) -> float:
	return clampf(-accel_body.y / G / 0.25, -1.0, 1.0)


func publish() -> void:
	var ok := not (Props.get_b("failures/adr") or Props.get_b("failures/adirs"))
	Props.set_v("instruments/adirs/valid", ok)
	Props.set_v("instruments/adirs/pitch_rad", Props.get_f("fdm/pitch_rad") if ok else 0.0)
	Props.set_v("instruments/adirs/roll_rad", Props.get_f("fdm/roll_rad") if ok else 0.0)
	Props.set_v("instruments/adirs/heading_deg", fposmod(rad_to_deg(Props.get_f("fdm/heading_rad")) - VAR_DEG, 360.0) if ok else 0.0)
	Props.set_v("instruments/adirs/track_deg", fposmod(rad_to_deg(Props.get_f("fdm/track_rad")) - VAR_DEG, 360.0) if ok else 0.0)
	Props.set_v("instruments/adirs/slip", slip_of(Props.get_v("fdm/accel_body", Vector3.ZERO)) if ok else 0.0)
