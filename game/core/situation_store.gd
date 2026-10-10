class_name SituationStore
extends RefCounted
## Files of saved flight situations (core/situation.gd): user://saves/<file>.json with
## the situation (full-precision floats) and <file>.png, a 320x180 thumbnail.
## <file> is the save name with characters unsafe in file names replaced.

const DIR := "user://saves/"
const THUMB := Vector2i(320, 180)


static func write(d: Dictionary, name: String, thumb: Image = null) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var base := DIR + file_name(name)
	var fa := FileAccess.open(base + ".json", FileAccess.WRITE)
	if fa == null:
		return "Cannot write %s.json" % base
	fa.store_string(JSON.stringify(d, "\t", false, true))
	fa.close()
	if thumb and not thumb.is_empty():
		var t := thumb.duplicate() as Image
		fit(t)
		t.save_png(base + ".png")
	elif FileAccess.file_exists(base + ".png"):
		DirAccess.remove_absolute(base + ".png")  # stale thumbnail of an older save
	return ""


static func read(file: String) -> Dictionary:
	var path := DIR + file + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## Metadata of every save, newest first, plus "file" and "thumb" (png path or "").
static func list() -> Array:
	var out := []
	var da := DirAccess.open(DIR)
	if da == null:
		return out
	for fname in da.get_files():
		if not fname.ends_with(".json"):
			continue
		var file := fname.get_basename()
		var d := read(file)
		if d.is_empty() or not d.has("meta"):
			continue
		var m: Dictionary = d.meta.duplicate()
		m.file = file
		m.thumb = DIR + file + ".png" if FileAccess.file_exists(DIR + file + ".png") else ""
		out.append(m)
	out.sort_custom(func(a, b): return float(a.get("unix", 0)) > float(b.get("unix", 0)))
	return out


static func delete(file: String) -> void:
	for ext in [".json", ".png"]:
		if FileAccess.file_exists(DIR + file + ext):
			DirAccess.remove_absolute(DIR + file + ext)


static func file_name(name: String) -> String:
	var s := name.strip_edges()
	for c in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "."]:
		s = s.replace(c, "_")
	return s if s != "" else "unnamed"


static func load_thumb(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img else null


## Viewport screenshot cropped to 16:9 and scaled to the thumbnail size (null headless).
static func grab_thumbnail(vp: Viewport) -> Image:
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	fit(img)
	return img


static func fit(img: Image) -> void:
	if img.get_size() == THUMB:
		return
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var cw := mini(w, h * 16 / 9)
	var ch := mini(h, w * 9 / 16)
	if cw != w or ch != h:
		img.copy_from(img.get_region(Rect2i((w - cw) / 2, (h - ch) / 2, cw, ch)))
	img.convert(Image.FORMAT_RGB8)
	img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_BILINEAR)
