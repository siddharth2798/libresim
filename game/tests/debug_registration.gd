extends Node
## Debug (windowed, the GPU draws the glyphs): runs RegistrationPaint on an aircraft's atlases and saves the
## repainted regions of every target as PNGs.
##   godot --path game --windowed --audio-driver Dummy res://tests/debug_registration.tscn -- --aircraft=c172 --out=<dir> [--texts=VT-LBR,VT-A]
## One <out>/<aircraft>_<text>_<atlas>_<n>.png per target: the target's erase rectangle plus 40 px around it.


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var id := "c172"
	var out := "user://"
	var texts := ["VT-LBR"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aircraft="): id = a.substr(11)
		elif a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--texts="): texts = a.substr(8).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	var def := AircraftDef.load_def(id)
	var section := def.section("registration")
	for text in texts:
		var plan := RegistrationPaint.plan(section, text)
		var done := {}
		for st in plan:
			if done.has(st.texture):
				continue
			done[st.texture] = true
			var atlas := load(def.dir + "/" + st.texture) as Texture2D
			var tex := await RegistrationPaint.texture(self, id, section, atlas, text, st.texture)
			if tex == null:
				print("NO TEXTURE for %s %s (no pixels from this renderer?)" % [text, st.texture])
				continue
			var img := tex.get_image()
			var n := 0
			for s in plan:
				if s.texture != st.texture:
					continue
				var r: Rect2i = s.erase.grow(40).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
				var f := "%s/%s_%s_%s_%d.png" % [out, id, text, st.texture.get_file().get_basename(), n]
				img.get_region(r).save_png(f)
				print("SAVED ", f)
				n += 1
	# the real path: apply() on the exterior model, then which surfaces got an override and from which atlas
	var root := (load(def.path("exterior")) as PackedScene).instantiate()
	add_child(root)
	await RegistrationPaint.apply(self, root, def)
	var n := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in (m.mesh.get_surface_count() if m.mesh != null else 0):
			var o := m.get_surface_override_material(i) as BaseMaterial3D
			if o != null and o.albedo_texture is ImageTexture:
				var base := (m.mesh.surface_get_material(i) as BaseMaterial3D).albedo_texture.resource_path.get_file()
				n[base] = int(n.get(base, 0)) + 1
	print("OVERRIDDEN SURFACES per atlas: ", n)
	get_tree().quit()
