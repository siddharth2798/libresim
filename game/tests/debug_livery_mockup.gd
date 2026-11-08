extends Control
## Probe (windowed): the real livery turntable with a test picture on both sides and the fin, saved as PNGs.
##   godot --path game --windowed --resolution 1000x760 --audio-driver Dummy res://tests/debug_livery_mockup.tscn -- --out=<dir> [--colors=red]
## The picture is red on the left, blue top right, so a flipped or misplaced decal is visible.

const COLORS := {
	"red": {"body": "#c8101a", "accent": "#f2f2f2", "stripe": "#26262b", "struts": "#26262b"},
	"navy": {"body": "#0d1f66", "accent": "#f5f5f5", "stripe": "#d1a61a", "struts": "#d1a61a"},
	"none": {},
}
var _out := "user://"
var _which := "red"
var _aid := "c172"


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--colors="): _which = a.substr(9)
		elif a.begins_with("--aircraft="): _aid = a.substr(11)
	DirAccess.make_dir_recursive_absolute(_out)
	var img := Image.create(300, 180, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	img.fill_rect(Rect2i(0, 0, 150, 180), Color(0.9, 0.1, 0.1))
	img.fill_rect(Rect2i(210, 0, 90, 70), Color(0.1, 0.2, 0.9))
	img.fill_rect(Rect2i(20, 120, 60, 40), Color(0, 0, 0))
	DirAccess.make_dir_recursive_absolute(LiveryStore.images_dir())
	img.save_png(LiveryStore.images_dir().path_join("probe_test.png"))
	var prev: Control = load("res://ui/menu/livery_preview.gd").new()
	prev.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(prev)
	var def := AircraftDef.load_def(_aid)
	prev.show_aircraft(def)
	var slot := {"image": "probe_test.png", "scale": 1.0, "dx": 0.0, "dy": 0.0, "mirror": true}
	prev.set_paint({"colors": COLORS[_which], "stickers": {"side": slot, "fin": slot}})
	for v in [["side_l", 0.0, 0.05], ["side_r", 3.1416, 0.05], ["three", -0.62, 0.22]]:
		prev._yaw = v[1]
		prev._pitch = v[2]
		prev._zoom = 1.3
		prev._apply_camera()
		for i in 150:
			await get_tree().process_frame
		var shot := get_viewport().get_texture().get_image()
		shot.save_png(_out.path_join("%s_%s_%s.png" % [_aid, _which, v[0]]))
		print("SAVED ", _out.path_join("%s_%s_%s.png" % [_aid, _which, v[0]]))
	get_tree().quit()
