class_name LiveryStore
extends RefCounted
## Presets and imported pictures, on this computer only (user://liveries/). A preset is one aircraft's
## setup entry ({colors, stickers}). A picture is re-encoded as PNG (metadata dropped), long side at
## most 512 px, and stored by the sha1 of those bytes so the same picture is one file.


const MAX_BYTES := 4 * 1024 * 1024
const LONG_SIDE := 512
const EXTS := ["png", "jpg", "jpeg", "webp"]


static func images_dir() -> String:
	return "user://liveries/images"


static func preset_dir(aircraft_id: String) -> String:
	return "user://liveries/%s" % aircraft_id


## {ok, image} or {ok: false, error}. error is one line for the page.
static func import_file(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if not EXTS.has(ext):
		return {"ok": false, "error": "Use a PNG, JPG or WebP."}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Could not read that file."}
	if f.get_length() > MAX_BYTES:
		f.close()
		return {"ok": false, "error": "That picture is over 4 MB."}
	f.close()
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return {"ok": false, "error": "That file is not a picture."}
	var sz := img.get_size()
	var long := maxi(sz.x, sz.y)
	if long > LONG_SIDE:
		var sc := float(LONG_SIDE) / float(long)
		img.resize(maxi(1, int(sz.x * sc)), maxi(1, int(sz.y * sc)), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	var buf := img.save_png_to_buffer()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(buf)
	var name := ctx.finish().hex_encode() + ".png"
	DirAccess.make_dir_recursive_absolute(images_dir())
	img.save_png(images_dir().path_join(name))
	return {"ok": true, "image": name}


static func load_image(file_name: String) -> Image:
	var name := file_name.get_file()
	if name == "" or name.contains(".."):
		return null
	var path := images_dir().path_join(name)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return null if img == null or img.is_empty() else img


## The preset file name (without .json), or "" when the name has no usable characters.
static func save_preset(aircraft_id: String, preset_name: String, entry: Dictionary) -> String:
	var n := safe_name(preset_name)
	if n == "" or aircraft_id == "":
		return ""
	DirAccess.make_dir_recursive_absolute(preset_dir(aircraft_id))
	var f := FileAccess.open(preset_dir(aircraft_id).path_join(n + ".json"), FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(entry))
	f.close()
	return n


static func load_preset(aircraft_id: String, preset_name: String) -> Dictionary:
	var n := safe_name(preset_name)
	if n == "":
		return {}
	var text := FileAccess.get_file_as_string(preset_dir(aircraft_id).path_join(n + ".json"))
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func list_presets(aircraft_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(preset_dir(aircraft_id))
	if dir == null:
		return out
	for fn in dir.get_files():
		if fn.get_extension() == "json":
			out.append(fn.get_basename())
	out.sort()
	return out


static func remove_preset(aircraft_id: String, preset_name: String) -> void:
	var n := safe_name(preset_name)
	if n != "":
		DirAccess.remove_absolute(preset_dir(aircraft_id).path_join(n + ".json"))


static func safe_name(preset_name: String) -> String:
	var s := ""
	for i in preset_name.length():
		var c := preset_name[i]
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == " " or c == "-" or c == "_"
		if ok:
			s += c
	return s.strip_edges().substr(0, 40).replace(" ", "_")
