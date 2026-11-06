class_name LiveCache
extends RefCounted
## The last successful live-weather fetch, so a flight with no connection can still start from it.
## user://live_weather.json. Tests point `path` somewhere else.


const PATH := "user://live_weather.json"
static var path := PATH


static func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func write(d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


static func clear() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
