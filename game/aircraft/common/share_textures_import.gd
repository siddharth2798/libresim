@tool
extends EditorScenePostImport
## Import script for a model whose glb carries copies of textures another model in the same folder already has
## (the C172 cockpit glb repeats the exterior's panel, panel parts and interior atlases: Godot extracts both as
## interior_<name>.png and exterior_<name>.png, and both end up in video memory). Each material texture
## <model>_<name>.png that is byte-identical to <other model>_<name>.png next to it is swapped for the other one, so
## the two models share one texture. Runs only when Godot imports the glb (editor or --import), never in the game.
## Set as import_script/path in the glb's .import file (aircraft/c172/models/interior.glb.import).


func _post_import(scene: Node) -> Object:
	var src := get_source_file()
	var dir := src.get_base_dir()
	var own := src.get_file().get_basename() + "_"
	var others: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "glb" and f.get_basename() + "_" != own:
			others.append(f.get_basename() + "_")
	var cache := {}
	_walk(scene, dir, own, others, cache)
	return scene


func _walk(n: Node, dir: String, own: String, others: Array[String], cache: Dictionary) -> void:
	if n is MeshInstance3D and n.mesh != null:
		for i in n.mesh.get_surface_count():
			_swap(n.mesh.surface_get_material(i), dir, own, others, cache)
		for i in n.get_surface_override_material_count():
			_swap(n.get_surface_override_material(i), dir, own, others, cache)
	for c in n.get_children():
		_walk(c, dir, own, others, cache)


func _swap(mat: Material, dir: String, own: String, others: Array[String], cache: Dictionary) -> void:
	if mat == null:
		return
	for p in mat.get_property_list():
		if p.type != TYPE_OBJECT:
			continue
		var tex = mat.get(p.name)
		if not tex is Texture2D or tex.resource_path == "":
			continue
		var shared := shared_path(tex.resource_path, dir, own, others, cache)
		if shared != "":
			mat.set(p.name, load(shared))


## The other model's identical copy of `path`, or "" (pure apart from the files; cached per path).
static func shared_path(path: String, dir: String, own: String, others: Array[String], cache: Dictionary) -> String:
	if cache.has(path):
		return cache[path]
	var out := ""
	var file := path.get_file()
	if path.get_base_dir() == dir and file.begins_with(own):
		var md5 := FileAccess.get_md5(path)
		for o in others:
			var cand := dir.path_join(o + file.substr(own.length()))
			if FileAccess.file_exists(cand) and FileAccess.get_md5(cand) == md5:
				out = cand
				break
	cache[path] = out
	return out
