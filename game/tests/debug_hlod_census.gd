extends "res://tests/debug_showcase.gd"
## Debug: what the camera of a showcase scene (tests/showcase_hlod_scenes.gd) has in view, by part of the flight scene:
## GeometryInstance3D nodes whose bounds centre is in the view frustum, and how many of them their draw distance
## (visibility range) keeps. Prints "CENSUS <group> in_view=<n> drawn=<n>" lines before the usual screenshot.
##   godot --audio-driver Dummy --path game res://tests/debug_hlod_census.tscn -- --scene=hlod_stand --quality=high
## Muted like every run (the showcase mutes the master bus too).


func save(suffix := "") -> void:
	AudioServer.set_bus_mute(0, true)
	var cam := get_viewport().get_camera_3d()
	if cam != null and f != null:
		var groups := {}
		for n in f.find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			if not gi.is_visible_in_tree():
				continue
			var c := gi.global_transform * gi.get_aabb().get_center()
			if not cam.is_position_in_frustum(c):
				continue
			var path := str(f.get_path_to(gi)).split("/")
			var key := "/".join(path.slice(0, mini(2, path.size() - 1))) if path.size() > 1 else str(path[0])
			var d := cam.global_position.distance_to(c)
			var end := gi.visibility_range_end
			var drawn := end <= 0.0 or d < end + gi.visibility_range_end_margin
			if gi.visibility_range_begin > 0.0 and d < gi.visibility_range_begin - gi.visibility_range_begin_margin:
				drawn = false
			if not gi.visibility_parent.is_empty():
				var p := gi.get_node_or_null(gi.visibility_parent) as GeometryInstance3D
				drawn = drawn and p != null and d < p.visibility_range_begin + p.visibility_range_begin_margin
			if not groups.has(key):
				groups[key] = [0, 0]
			groups[key][0] += 1
			groups[key][1] += 1 if drawn else 0
		var keys := groups.keys()
		keys.sort_custom(func(a, b): return groups[a][0] > groups[b][0])
		for k in keys.slice(0, 25):
			print("CENSUS %s in_view=%d drawn=%d" % [k, groups[k][0], groups[k][1]])
	await super.save(suffix)
