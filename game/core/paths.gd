class_name Paths
## Locations of processed data. During development the data lives next to the
## project (free-sim/data/processed); an exported build will ship it beside the binary.

static func data_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join("../data/processed").simplify_path()
	return OS.get_executable_path().get_base_dir().path_join("data")


static func data(rel: String) -> String:
	return data_dir().path_join(rel)


static func load_json(rel: String) -> Variant:
	var f := FileAccess.open(data(rel), FileAccess.READ)
	if f == null:
		push_error("missing data file: " + data(rel))
		return null
	return JSON.parse_string(f.get_as_text())


static func load_res_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing file: " + path)
		return null
	return JSON.parse_string(f.get_as_text())
