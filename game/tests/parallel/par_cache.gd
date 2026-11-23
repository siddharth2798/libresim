extends RefCounted
## The launcher's timings cache: <repo>/.cache/tests/timings.json (gitignored, this computer only). It holds what
## the last runs measured so the next run can start the longest jobs first and size the memory budget:
##   suites:     suite path -> ms the suite took in its worker (its load, every test but the parted ones)
##   parted:     "<suite path>::<test>" -> ms of all its parts together
##   peaks:      suite path or parted key -> peak resident bytes of a worker that ran it (alone: the measured peak;
##               in a batch: the lowest batch peak seen, an upper bound)
##   startup_ms: what starting one worker costs (Godot, autoloads, the runner) beyond its suites
## A new value is averaged with the old one; a missing file or entry just means the defaults (par_plan.gd).

const VERSION := 1


static func dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../.cache/tests").simplify_path()


static func file() -> String:
	return dir().path_join("timings.json")


static func empty() -> Dictionary:
	return {"version": VERSION, "suites": {}, "parted": {}, "peaks": {}, "startup_ms": 0}


static func read(path: String = "") -> Dictionary:
	var f := FileAccess.open(path if path != "" else file(), FileAccess.READ)
	if f == null:
		return empty()
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary or int(d.get("version", 0)) != VERSION:
		return empty()
	for k in ["suites", "parted", "peaks"]:
		if not d.get(k) is Dictionary:
			d[k] = {}
	return d


static func write(d: Dictionary, path: String = "") -> void:
	var p := path if path != "" else file()
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, " ", false))


## Folds one measurement into the cache entry: the mean of the old and the new value (the new one when none).
static func blend(table: Dictionary, key: String, value: int) -> void:
	var old := int(table.get(key, 0))
	table[key] = value if old <= 0 else (old + value) / 2


## A higher peak counts at once, a lower one halves the gap: memory matters more when it is underrated.
static func blend_peak(table: Dictionary, key: String, value: int) -> void:
	var old := int(table.get(key, 0))
	table[key] = value if old <= 0 else maxi(value, (old + value) / 2)
