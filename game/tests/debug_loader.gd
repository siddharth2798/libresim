extends Node
## Debug: watch the loader film in a real window. Starts a flight through the start screen's own Fly button (the real
## path, like probe_real_start fly_now), then saves a frame every --every seconds for --secs and logs what the loader
## waits on: whether the root veil is up, the terrain's shown nodes and pending tiles, and the airport builder.
## Needs a display. Never touches the player's files (scratch save path, settings kept in memory).
##   godot --path game --resolution 1920x1080 res://tests/debug_loader.tscn -- --out=<dir> [--setup=<json>]
##       [--secs=14] [--every=0.2]
## Writes <dir>/f_NNN.png and prints one "LOADER t=.. veil=.. nodes=.. pending=.. apt_busy=.. status=.." line per frame.

const FLIGHT := "res://world/flight.tscn"


class Watch extends Node:
	var out := ""
	var secs := 14.0
	var every := 0.2
	var t := 0.0
	var next := 0.0
	var n := 0
	var started := false

	func _process(dt: float) -> void:
		var cs := get_tree().current_scene
		if not started:
			if cs == null or cs.scene_file_path != FLIGHT:
				# The veil goes up before the scene change: log it too, from the click.
				if BusyOverlay.root_veil(get_tree()) == null:
					return
			started = true
		t += dt
		if t < next:
			return
		next = t + every
		var veil := BusyOverlay.root_veil(get_tree())
		var nodes := -1
		var pending := -1
		var busy := false
		if cs != null and cs.scene_file_path == FLIGHT and cs.get_node_or_null("Terrain") != null:
			var ter: TerrainQuadtree = cs.get_node("Terrain")
			nodes = ter.visible_nodes
			pending = ter.pending_tiles
			busy = cs.get_node("Airports").busy()
		var film := "-"
		if veil != null:
			film = "%s/%s size=%s film_size=%s" % [veil._film.visible, veil._film.texture != null, veil.size, veil._film.size]
		print("LOADER t=%.2f veil=%s film=%s nodes=%d pending=%d apt_busy=%s status=%s" % [t, veil != null and veil.visible,
			film, nodes, pending, busy, veil._label.text if veil != null else ""])
		get_viewport().get_texture().get_image().save_png(out.path_join("f_%03d.png" % n))
		n += 1
		if t >= secs:
			get_tree().quit()


func _ready() -> void:
	var w := Watch.new()
	var setup := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"out": w.out = kv[1]
			"secs": w.secs = float(kv[1])
			"every": w.every = float(kv[1])
			"setup": setup = JSON.parse_string(FileAccess.get_file_as_string(kv[1]))
	DirAccess.make_dir_recursive_absolute(w.out)
	Session.skip_menu = false
	Session.interactive_override = 0
	Session.save_path = "user://_debug_loader_last_flight.json"
	Session.setup = Session.DEFAULT.duplicate(true)
	for k in setup:
		if Session.setup.has(k):
			Session.setup[k] = setup[k]
	get_tree().root.add_child.call_deferred(w)
	var screen: Control = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(screen)
	# A timer, not frames: an unfocused window may draw few frames, and the screen needs its first layout.
	await get_tree().create_timer(1.0).timeout
	screen.go("flight")
	screen.screen("flight").fly_btn.pressed.emit()
