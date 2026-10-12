class_name LegacyMigrate
extends RefCounted
## The game was called "free-sim" before it became "libresim", and Godot keeps user data
## (saves, key and joystick bindings, options, recordings) in a folder named after the
## project. Copy anything from the old folder that the new one does not have yet, once.


static func run() -> void:
	var new_dir := OS.get_user_data_dir()
	var old_dir := new_dir.get_base_dir().path_join("free-sim")
	if old_dir == new_dir or not DirAccess.dir_exists_absolute(old_dir):
		return
	if FileAccess.file_exists(new_dir.path_join(".migrated")):
		return
	var n := _copy_missing(old_dir, new_dir)
	var f := FileAccess.open(new_dir.path_join(".migrated"), FileAccess.WRITE)
	if f:
		f.store_string("from free-sim: %d files" % n)
	if n > 0:
		print("libresim: copied %d settings / saves from the old free-sim folder" % n)


static func _copy_missing(src: String, dst: String) -> int:
	var n := 0
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return 0
	for f in d.get_files():
		var to := dst.path_join(f)
		if not FileAccess.file_exists(to) and DirAccess.copy_absolute(src.path_join(f), to) == OK:
			n += 1
	for sub in d.get_directories():
		n += _copy_missing(src.path_join(sub), dst.path_join(sub))
	return n
