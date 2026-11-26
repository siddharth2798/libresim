extends Node
## What the A320 FCU windows show (FcuWindows, shared by the glareshield LCD and the FCU card): managed = dashes and a dot,
## selected = the digits; V/S only in V/S mode; SPD/MACH and HDG-V/S / TRK-FPA relabel; blank without power. The model's
## static label quads are hidden under the live strip.

const KEEP := ["controls/fcu/spd_managed", "controls/fcu/spd_mach", "controls/fcu/spd_kt", "controls/fcu/mach_sel", "controls/fcu/hdg_managed",
	"controls/fcu/hdg_deg", "controls/fcu/trk_fpa", "controls/fcu/alt_ft", "controls/fcu/vs_managed", "controls/fcu/vs_fpm",
	"ap/fma/vertical", "fdm/tas_mps", "fdm/cas_mps", "fdm/mach", "systems/electrical/avionics_powered"]

var _saved := {}


func teardown() -> void:
	for p in _saved:
		if _saved[p] == null:
			Props._p.erase(p)
		else:
			Props.set_v(p, _saved[p])
	_saved.clear()


func _keep() -> void:
	for p in KEEP:
		_saved[p] = Props.get_v(p, null)


func test_fcu_windows_managed_and_selected() -> String:
	_keep()
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("controls/fcu/spd_kt", 250.0)
	Props.set_v("controls/fcu/spd_mach", false)
	Props.set_v("controls/fcu/spd_managed", true)
	var s := FcuWindows.spd()
	if s.text != "---" or not s.dot:
		return "managed SPD %s" % s
	Props.set_v("controls/fcu/spd_managed", false)
	s = FcuWindows.spd()
	if s.text != "250" or s.dot or s.label != "SPD":
		return "selected SPD %s" % s
	Props.set_v("controls/fcu/hdg_deg", 5.0)
	Props.set_v("controls/fcu/hdg_managed", true)
	var h := FcuWindows.hdg()
	Props.set_v("controls/fcu/hdg_managed", false)
	var h2 := FcuWindows.hdg()
	if h.text != "---" or not h.dot or h2.text != "005" or h2.dot:
		return "HDG %s / %s" % [h, h2]
	Props.set_v("controls/fcu/alt_ft", 7000.0)
	Props.set_v("controls/fcu/vs_managed", true)
	var a := FcuWindows.alt()
	if a.text != "07000" or not a.dot:
		return "ALT %s" % a
	Props.set_v("controls/fcu/vs_fpm", -700.0)
	Props.set_v("ap/fma/vertical", "ALT")
	var v := FcuWindows.vs()
	Props.set_v("ap/fma/vertical", "V/S\nG/S")  # V/S active with the glide slope armed
	var v2 := FcuWindows.vs()
	if v.text != "-----" or v2.text != "-0700":
		return "V/S %s / %s" % [v, v2]
	return ""


func test_fcu_windows_relabel_and_power() -> String:
	_keep()
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("controls/fcu/spd_managed", false)
	Props.set_v("controls/fcu/spd_mach", true)
	Props.set_v("controls/fcu/spd_kt", 300.0)
	Props.set_v("controls/fcu/mach_sel", 0.78)  # the Mach window shows its own value, not a conversion of the knots
	var s := FcuWindows.spd()
	if s.label != "MACH" or s.text != ".78":
		return "MACH %s" % s
	Props.set_v("controls/fcu/trk_fpa", true)
	Props.set_v("controls/fcu/vs_fpm", 1000.0)
	Props.set_v("fdm/tas_mps", 100.0)
	Props.set_v("ap/fma/vertical", "V/S")
	var v := FcuWindows.vs()
	if FcuWindows.hdg().label != "TRK" or v.label != "FPA" or FcuWindows.mode_label() != "TRK FPA" or v.text != "+2.9":
		return "TRK/FPA %s %s %s" % [FcuWindows.hdg(), v, FcuWindows.mode_label()]
	Props.set_v("controls/fcu/trk_fpa", false)
	if FcuWindows.mode_label() != "HDG V/S":
		return "HDG V/S label"
	Props.set_v("systems/electrical/avionics_powered", false)
	if FcuWindows.powered() or FcuLcd.signature() != "":
		return "an unpowered FCU should be blank"
	return ""


func test_static_fcu_labels_are_hidden_under_the_live_strip() -> String:
	var glb: Node3D = (load("res://aircraft/a320/models/interior.glb") as PackedScene).instantiate()
	var lcd := FcuLcd.new()
	var spec: Dictionary = AircraftDef.load_def("a320").section("cockpit").fcu_lcd.hide
	lcd._hide(glb, spec)
	var src := glb.find_child(str(spec.mesh), true, false) as MeshInstance3D
	var hidden := 0
	for i in src.mesh.get_surface_count():
		var m := src.mesh.surface_get_material(i)
		if m != null and m.resource_name in spec.materials:
			var o := src.get_surface_override_material(i) as BaseMaterial3D
			if o != null and o.albedo_color.a == 0.0:
				hidden += 1
	lcd.free()
	glb.free()
	return "" if hidden == 2 else "hid %d of the 2 static FCU label surfaces" % hidden
