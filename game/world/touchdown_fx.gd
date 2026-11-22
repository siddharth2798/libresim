class_name TouchdownFx
extends Node3D
## Touchdown effects of each wheel the runway has to spin up (TouchdownDetect: a main wheel landing after being
## airborne, a nose wheel only when it lands sliding sideways; FDM gear.info, no extra Props):
##   squeal  TyreSqueal, a 3D sound at that wheel, once per wheel per touchdown
##   smoke   TyreSmoke, a soft white puff laid behind that wheel that thins away over a few seconds
##   marks   TouchdownMarks, a fresh dark tyre streak on the runway at that spot (drawn by runway_v2.gdshader), kept
##           in saved flights
##   ground  GroundFx: rain splashes, wheel spray, engine wash and dust (a dust puff on a dry grass touchdown)
## The faster the ground speed and the harder the sink, the louder, bigger and darker.
## Never on a takeoff (see TouchdownDetect). Paused or in a replay nothing new starts.

var fdm_node: FdmNode
var detect := TouchdownDetect.new()
var squeal: TyreSqueal
var smoke: TyreSmoke
var marks: TouchdownMarks
var ground: GroundFx
var _situation := -1  # Props meta/situation seen last: a loaded flight is placed, not landed


## Smoke strength 0..1 of a wheel's spin-up from its slip (m/s, ground speed minus rim speed) and sink rate (m/s):
## 0 when the tyre is (nearly) turning at the ground speed already.
static func puff(slip: float, sink: float) -> float:
	if slip < TouchdownDetect.MIN_SLIP:
		return 0.0
	var speed_f := clampf((slip - TouchdownDetect.MIN_SLIP) / 25.0, 0.0, 1.0)
	var sink_f := clampf(sink / 2.5, 0.0, 1.0)
	return clampf(0.1 + speed_f * (0.35 + 0.65 * sink_f), 0.0, 1.0)


func setup(f: FdmNode, def: AircraftDef = null, airports: AirportBuilder = null) -> void:
	fdm_node = f
	marks = TouchdownMarks.new()
	marks.name = "Marks"
	marks.airports = airports
	add_child(marks)
	if def == null:
		def = AircraftDef.current()
	squeal = TyreSqueal.new()
	squeal.name = "Squeal"
	add_child(squeal)
	squeal.setup(f, def)
	smoke = TyreSmoke.new()
	smoke.name = "Smoke"
	add_child(smoke)
	smoke.setup(def.section("touchdown"), func(w: String) -> Vector3: return TouchdownDetect.wheel_enu(fdm_node.fdm, w))
	ground = GroundFx.new()
	ground.name = "Ground"
	add_child(ground)
	ground.setup(f, def, airports)


func clear() -> void:
	if squeal:
		squeal.stop_all()
		smoke.stop_all()
	if marks:
		marks.clear()
	if ground:
		ground.clear()
	detect.clear()


func _physics_process(dt: float) -> void:
	if fdm_node == null or fdm_node.paused:
		return
	if fdm_node.replaying:
		detect.clear()  # taking control again starts like a ground / loaded start: no touchdown from the jump
		return
	var sit := int(Props.get_v("meta/situation", 0))
	if sit != _situation:
		_situation = sit
		detect.clear()  # a loaded save puts the aircraft down: like a ground start, no touchdown from the jump
	var gear := fdm_node.fdm.gear
	for ev in detect.step(gear.contacts, gear.info, fdm_node.fdm.velocity_ned(), dt):
		touchdown(ev)


## One wheel spun up (a TouchdownDetect event): squeal, smoke and a tyre mark.
func touchdown(ev: Dictionary) -> void:
	squeal.play(ev)
	if ground:
		ground.touchdown(ev)
	var k := puff(Vector2(ev.slip, ev.vlat).length(), maxf(float(ev.sink), absf(float(ev.vlat))))
	if k > 0.0:
		smoke.emit(ev.wheel, k, ev.track, ev.gs)
		if marks:
			marks.add(float(ev.e), float(ev.n), float(ev.track), 0.35 + 0.6 * k)
