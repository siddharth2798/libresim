extends Node
## World sounds (docs/AUDIO-PLAN.md): airport vehicle engines from speed (WorldSound, VehicleSound), the jetway motor while it
## moves (JetwaySound), thunder after lightning (Thunder). Dummy audio server: values only.


func _near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func test_world_vehicle_state() -> String:
	var idle := WorldSound.vehicle_state("pushback_tug", 0.0)
	var push := WorldSound.vehicle_state("pushback_tug", 3.0)
	var back := WorldSound.vehicle_state("pushback_tug", -3.0)
	if not (_near(idle[0], 0.55) and _near(push[0], 1.0) and push[1] > idle[1] and back == push):
		return "the tug idles and revs with speed, either way: %s %s %s" % [idle, push, back]
	if WorldSound.vehicle_state("gpu", 5.0) != WorldSound.vehicle_state("gpu", 0.0):
		return "the GPU runs steady"
	if WorldSound.vehicle_state("nothing", 3.0) != [0.0, 1.0]:
		return "an unknown kind is silent"
	for k in WorldSound.KINDS:
		if not ResourceLoader.exists(WorldSound.path(WorldSound.KINDS[k].file)):
			return "%s: %s missing" % [k, WorldSound.KINDS[k].file]
	return ""


func test_world_vehicle_sound_follows_motion() -> String:
	var car := Node3D.new()
	add_child(car)
	var s := VehicleSound.attach(car, "follow_me")
	var err := ""
	if s == null or s.player == null or s.player.stream == null:
		err = "the follow-me car gets an engine"
	else:
		for i in 30:
			car.position.x += 0.2  # 12 m/s at 60 Hz
			s._process(1.0 / 60.0)
		if s.speed < 6.0 or s.player.pitch_scale <= WorldSound.vehicle_state("follow_me", 0.0)[1]:
			err = "it revs as it drives: %.1f m/s, pitch %.2f" % [s.speed, s.player.pitch_scale]
		var before := s.speed
		car.position.x += 400.0  # an origin shift: no speed
		s._process(1.0 / 60.0)
		if err.is_empty() and s.speed > before + 0.01:
			err = "a jump is not speed"
	if VehicleSound.attach(car, "nothing") != null:
		err = "an unknown kind adds nothing"
	if s and s.player:
		s.player.stop()
	car.free()
	return err


func test_world_jetway_moving() -> String:
	if JetwaySound.moving(Vector2(-1, -1), Vector2(0.2, 0)):
		return "the first sample never counts"
	if not JetwaySound.moving(Vector2(0.2, 0), Vector2(0.21, 0)) or not JetwaySound.moving(Vector2(1, 0.5), Vector2(1, 0.6)):
		return "bridge or canopy travel is moving"
	if JetwaySound.moving(Vector2(1, 1), Vector2(1, 1)):
		return "docked and still is quiet"
	return "" if ResourceLoader.exists(WorldSound.path("jetway_motor_loop.wav")) else "jetway_motor_loop.wav missing"


func test_world_thunder() -> String:
	var near := Thunder.plan(1.0)
	var far := Thunder.plan(5.0)
	if not _near(near.delay, 1000.0 / 340.0) or far.delay <= near.delay or far.vol >= near.vol or far.pitch >= near.pitch:
		return "thunder arrives later, quieter and duller from further: %s %s" % [near, far]
	var t := Thunder.new()
	add_child(t)
	t.strike(1.0)
	var err := ""
	if t.step(1.0).size() != 0 or t.pending.size() != 1:
		err = "the peal waits for the sound to arrive"
	elif t.step(2.0).size() != 1 or not t.pending.is_empty():
		err = "then it plays once"
	for i in 10:
		t.strike(3.0)
	if err.is_empty() and t.pending.size() != Thunder.MAX_PENDING:
		err = "at most %d peals wait" % Thunder.MAX_PENDING
	for p in t.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	t.free()
	OS.delay_msec(100)
	return err
