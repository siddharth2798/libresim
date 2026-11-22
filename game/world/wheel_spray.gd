class_name WheelSpray
extends Node3D
## What one wheel throws up while it rolls (GroundFx feeds it every frame):
##   spray  water off a wet surface: droplets thrown up and out of the tyre's path that slow into a trailing mist;
##          from walking pace up, more and higher with ground speed and with the water on the surface
##   tail   rooster tail of a main wheel at takeoff / landing speeds: a tall plume behind the tyre (paved, wet)
##   dust   off dry grass or dirt: a trail while rolling and a puff when the wheel lands (touchdown())
## The particles leave the tyre with a fraction of the ground speed and air drag stops them, so the spray stays near
## where it was thrown and streams back behind the aircraft. Emitters whose preset count is 0 are never built.

const MIN_GS := 2.5  # m/s: slower and the tyre only pushes the water aside
const PUFF_S := 0.45  # s of a touchdown dust puff

var width := 0.2  # m across the tyres of this leg (aircraft.json touchdown.legs)
var main := true  # a main wheel (rooster tail) or a nose / tail wheel
var spray: GroundEmitter
var tail: GroundEmitter
var dust: GroundEmitter
var _puff := 0.0


## Spray strength 0..1 at ground speed gs (m/s) on a surface this wet (environment/wetness 0..1); unpaved ground
## (wet grass) throws far less. 0 when dry or stopped.
static func spray_rate(gs: float, wet: float, paved := true) -> float:
	if gs < MIN_GS or wet < 0.08:
		return 0.0
	return sqrt(clampf((gs - MIN_GS) / 35.0, 0.0, 1.0)) * smoothstep(0.08, 0.6, wet) * (1.0 if paved else 0.35)


## Rooster tail strength 0..1: takeoff and landing speeds on a really wet runway.
static func tail_rate(gs: float, wet: float, paved := true) -> float:
	return smoothstep(20.0, 45.0, gs) * smoothstep(0.25, 0.7, wet) if paved else 0.0


## Dust strength 0..1 rolling at gs (m/s): only off the pavement and only while the ground is dry.
static func dust_rate(gs: float, wet: float, paved: bool) -> float:
	if paved:
		return 0.0
	return smoothstep(2.0, 20.0, gs) * (1.0 - smoothstep(0.1, 0.35, wet))


## counts: GroundFxQuality.counts(); builds the emitters that have a count, sizes them all.
func set_counts(c: Dictionary) -> void:
	spray = _ensure(spray, "spray", int(c.get("spray", 0)))
	tail = _ensure(tail, "tail", int(c.get("tail", 0)) if main else 0)
	dust = _ensure(dust, "dust", int(c.get("dust", 0)))


## The wheel landed: a dust puff when the ground there is dry and unpaved.
func touchdown(wet: float, paved: bool) -> void:
	if not paved and wet < 0.35:
		_puff = PUFF_S


## One frame. on: the tyre touches the ground; src / vel: contact point and aircraft velocity (render frame);
## fwd: unit track direction (render frame); gs m/s; wet 0..1; drift: wind as a render-frame push (m/s^2).
func update(on: bool, src: Vector3, vel: Vector3, fwd: Vector3, gs: float, wet: float, paved: bool, drift: Vector3, dt: float) -> void:
	_puff = maxf(_puff - dt, 0.0)
	var r_spray := spray_rate(gs, wet, paved) if on else 0.0
	var r_tail := tail_rate(gs, wet, paved) if on else 0.0
	var r_dust := maxf(dust_rate(gs, wet, paved) if on else 0.0, 1.0 if _puff > 0.0 else 0.0)
	if spray:
		spray.set_rate(r_spray)
		if r_spray > 0.0:
			_aim(spray, src, vel, (fwd * 0.35 + Vector3.UP).normalized(), 0.08 * gs + 0.5, 0.2 * gs + 1.5, -5.0, drift)
	if tail:
		tail.set_rate(r_tail)
		if r_tail > 0.0:
			_aim(tail, src - fwd * 0.4, vel, (fwd * 0.3 + Vector3.UP).normalized(), 0.1 * gs, 0.36 * gs, -9.8, drift * 0.5)  # a fan
	if dust:
		dust.set_rate(r_dust)
		if r_dust > 0.0:
			var kick := 2.5 if _puff > 0.0 else 0.0
			_aim(dust, src, vel, (fwd * -0.2 + Vector3.UP).normalized(), 0.3, 0.06 * gs + 1.5 + kick, 0.25, drift)


func clear() -> void:
	_puff = 0.0
	for e in [spray, tail, dust]:
		if e:
			e.clear()


func _aim(e: GroundEmitter, src: Vector3, vel: Vector3, dir: Vector3, v0: float, v1: float, g: float, drift: Vector3) -> void:
	e.place(src, vel)
	var p := e.proc
	p.emission_box_extents = Vector3(width * 0.5 + 0.12, 0.05, width * 0.5 + 0.12)
	p.direction = dir
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = Vector3(drift.x, g, drift.z)


func _ensure(e: GroundEmitter, kind: String, n: int) -> GroundEmitter:
	if e == null and n <= 0:
		return null
	if e == null:
		e = GroundEmitter.new(kind)
		e.name = kind.capitalize()
		var sz := 0.7 + 0.5 * width  # a wide bogie throws a bigger cloud than a light-aircraft tyre
		e.proc.scale_min *= sz
		e.proc.scale_max *= sz
		add_child(e)
	e.set_capacity(n)
	return e
