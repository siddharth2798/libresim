extends Node
## Debug: what the runway / taxiway meshes cost (speed fix 5, world/airport_builder.gd). Starts a flight, times the load, then
## prints one RWNEAR line: the nodes under Airports, draw calls and objects (RenderingServer.get_rendering_info, main
## viewport visible info), the loader wait and memory. Needs a window (draw calls).
##   godot --audio-driver Dummy --path game res://tests/debug_runways_nearby.tscn -- --quality=low --airport=VABB [--air_ft=12000]
## Uses only calls that exist before and after the change, so it also runs on an older checkout (the "before" numbers).

const Setup := preload("res://tests/showcase_setup.gd")


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var airport := "VABB"
	var air_ft := 0.0
	var secs := 3.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--airport="):
			airport = a.substr(10)
		elif a.begins_with("--air_ft="):
			air_ft = float(a.substr(9))
		elif a.begins_with("--secs="):
			secs = float(a.substr(7))
	await get_tree().create_timer(1.0).timeout
	var setup := {"airport": airport, "time_h": 12.0, "visibility_m": 30000.0}
	if air_ft > 0.0:
		setup.merge({"start": "air", "air_ft": air_ft, "air_nm": 3.0, "air_kt": 100.0})
	Setup.setup_session({"weather": "Fair", "view": "chase", "setup": setup})
	var mem0 := OS.get_static_memory_usage()
	var t0 := Time.get_ticks_usec()
	var f: Node = load("res://world/flight.tscn").instantiate()
	add_child(f)
	var add_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var ab: Node = f.get_node("Airports")
	var terrain = f.get_node("Terrain")
	var wait_ms := -1.0
	var rw_ms := -1.0  # until the runway / taxiway meshes were in (AirportBuilder.busy() false)
	var frames := 0
	while frames < 1800:
		await get_tree().process_frame
		frames += 1
		if rw_ms < 0.0 and not ab.busy():
			rw_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		if wait_ms < 0.0 and not f.loader_holds(terrain.visible_nodes, terrain.pending_tiles, ab.busy(), 0.0, false):
			wait_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		if wait_ms >= 0.0 and float(Time.get_ticks_usec() - t0) / 1000.0 > wait_ms + 6000.0:
			break
	var fdm: FdmNode = f.get_node("Fdm")
	fdm.paused = true
	var vp := get_viewport().get_viewport_rid()
	var n := 0
	var draws := 0.0
	var objs := 0.0
	var vdraws := 0.0
	var vobjs := 0.0
	var t1 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t1) < secs * 1000.0:
		await RenderingServer.frame_post_draw
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		vdraws += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		vobjs += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		n += 1
	print("RWNEAR airport=%s air_ft=%d preset=%s renderer=%s airports_nodes=%d draws_total=%.0f objects_total=%.0f draws_view=%.0f objects_view=%.0f load_wait_ms=%.0f runways_ready_ms=%.0f add_child_ms=%.0f static_mem_mb=%.1f video_mem_mb=%.1f tex_mem_mb=%.1f" % [
		airport, int(air_ft), Graphics.preset, Graphics.renderer(), ab.get_child_count(), draws / n, objs / n, vdraws / n, vobjs / n,
		wait_ms, rw_ms, add_ms, float(OS.get_static_memory_usage() - mem0) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
	f.queue_free()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
