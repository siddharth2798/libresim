extends Node
## Debug / integration check for instant replay. Run (with a display):
##   godot --path game res://tests/debug_replay.tscn -- --airport=VABB --runway=27 --air=1500
## Flies 20 s, replays from 15 s back at 2x, screenshots the replay bar
## ($FREESIM_SHOTS or /tmp)/replay_bar.png, takes control, flies 10 s and checks it flies.

var f: Node
var replay: Replay
var phase := 0
var t := 0.0
var _kias_at_take := 0.0
var _replay_t0 := 0.0


func _ready() -> void:
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	replay = f.get_node_or_null("Replay")
	if replay == null:  # not yet wired into flight.tscn: add it here
		replay = Replay.new()
		replay.name = "Replay"
		f.add_child(replay)
	if f.get_node_or_null("UI/ReplayBar") == null:
		var bar := ReplayBar.new()
		bar.name = "ReplayBar"
		bar.replay = replay
		f.get_node("UI").add_child(bar)


func _kias() -> float:
	return Units.mps_to_kt(Props.get_f("fdm/cas_mps"))


func _process(dt: float) -> void:
	t += dt
	match phase:
		0:
			if replay.clock >= 20.0:
				print("RP flew %.1f s, %d frames (%.1f MB buffer), %.0f KIAS alt %.0f ft" % [replay.clock, replay.buffer.size(),
					replay.buffer.memory_bytes() / 1048576.0, _kias(), Units.m_to_ft(Props.get_f("fdm/alt_m"))])
				replay.start_replay(15.0)
				replay.set_speed(2.0)
				_replay_t0 = replay.t
				phase = 1
				t = 0.0
		1:
			if t > 2.5:
				var dir := OS.get_environment("FREESIM_SHOTS")
				var path := (dir if dir != "" else "/tmp").path_join("replay_bar.png")
				get_viewport().get_texture().get_image().save_png(path)
				var fn: FdmNode = f.get_node("Fdm")
				var b: ReplayBar = f.get_node("UI/ReplayBar")
				print("RP bar rect %s visible %s root %s" % [b._bar.get_global_rect(), b._bar.is_visible_in_tree(), b.get_global_rect()])
				print("RP replay advanced %.2f s in %.2f s real (2x); asi gauge %.0f kt; fdm held: %s; saved %s" % [
					replay.t - _replay_t0, t, Props.get_f("instruments/asi_kt"), fn.replaying, path])
				_kias_at_take = _kias()
				replay.take_control()
				phase = 2
				t = 0.0
		2:
			if t > 10.0:
				var crashed := Props.get_b("damage/crashed")
				var k := _kias()
				var ok := not crashed and k > 55.0 and k < 160.0 and not replay.active
				print("RP took control at %.0f KIAS; 10 s later %.0f KIAS alt %.0f ft crashed %s frames %d -> %s" % [
					_kias_at_take, k, Units.m_to_ft(Props.get_f("fdm/alt_m")), crashed, replay.buffer.size(), "OK" if ok else "FAIL"])
				get_tree().quit(0 if ok else 1)
