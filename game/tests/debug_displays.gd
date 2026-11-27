extends Node
## Debug / preview: renders the A320 glass panel (aircraft/a320/panel.json through InstrumentPanel) for
## a few plausible flight states and saves PNGs to $FREESIM_SHOTS (default: the user data dir):
##   godot --path game res://tests/debug_displays.tscn --audio-driver Dummy
## displays_cruise.png (FL350 M0.78), displays_approach.png (final, ILS, gear and flaps out),
## displays_sd_<page>.png (the SD pages), displays_mcdu.png, displays_cstr.png (SID / STAR limits on the ND and MCDU F-PLN).
## DisplayFixtures.set_state() is shared with tests/test_displays.gd.

var _vp: SubViewport
var _panel: InstrumentPanel
var _steps := []
var _frame := 0
var _dir := ""


func _ready() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/a320/panel.json"))
	var l := InstrumentPanel.normalize(raw)
	_vp = SubViewport.new()
	_vp.size = Vector2i(InstrumentPanel.natural_size_of(l))
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_panel = InstrumentPanel.new()
	_panel.layout_override = l
	_panel.size = Vector2(_vp.size)
	_vp.add_child(_panel)
	_dir = (OS.get_environment("FREESIM_SHOTS") if OS.get_environment("FREESIM_SHOTS") != "" else OS.get_user_data_dir()) + "/"
	DirAccess.make_dir_recursive_absolute(_dir)
	_steps = [["cruise", {}], ["approach", {}], ["sd_FUEL", {"sd/page": "FUEL"}], ["sd_WHEEL", {"sd/page": "WHEEL"}],
		["sd_FCTL", {"sd/page": "FCTL"}], ["mcdu", {"mcdu/page": "PERF", "mcdu/scratch": "138"}], ["cstr", _cstr()]]


## A STAR ahead with one limit met and one missed: the ND circles (CSTR on: the values), the MCDU F-PLN SPD/ALT lines.
static func _cstr() -> Dictionary:
	var c := {"VELKO": {"lo": 12000.0, "hi": 0.0, "spd": 230.0, "proc": "STAR"}, "BB258": {"lo": 11000.0, "hi": 11000.0, "spd": 0.0, "proc": "STAR"}}
	return {"mcdu/page": "FPLN", "controls/efis/nd_filter": 1, "controls/nd/range_nm": 80, "controls/gps/target": "VELKO", "controls/gps/route_next": ["BB258", "VABB"],
		RouteSetup.CSTR_PROP: c, "avionics/fms/cstr_state": {"VELKO": "met", "BB258": "missed"},
		"instruments/nd/route": [{"id": "VELKO", "x": 40000.0, "y": 12000.0, "cstr": "230/+FL120", "state": "met"},
			{"id": "BB258", "x": 60000.0, "y": 9000.0, "cstr": "FL110", "state": "missed"}, {"id": "VABB", "x": 91000.0, "y": 5000.0}],
		"avionics/fms/legs": [{"ident": "VELKO", "course": 74.0, "dist_nm": 12.0}, {"ident": "BB258", "course": 98.0, "dist_nm": 11.0},
			{"ident": "VABB", "course": 97.0, "dist_nm": 17.0}]}


func _process(_dt: float) -> void:
	_frame += 1
	if _frame % 6 != 0:
		return
	var i := _frame / 6 - 1
	if i > 0:  # save what the previous step set up
		_vp.get_texture().get_image().save_png(_dir + "displays_%s.png" % _steps[i - 1][0])
	if i >= _steps.size():
		get_tree().quit()
		return
	var s: Array = _steps[i]
	DisplayFixtures.set_state("approach" if s[0] != "cruise" else "cruise")
	for k in s[1]:
		Props.set_v(k, s[1][k])
	_panel.refresh()
