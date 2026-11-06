extends RefCounted
## A320 material shading (aircraft/common/material_finish.gd). The table and the cabin-glow
## factor are pure; nothing here loads a glb.


func test_a320_material_table() -> String:
	var t: Dictionary = MaterialFinish.table("a320")
	var want := {
		"a320_fuselage": [0.32, 0.0],
		"a320_engine": [0.45, 0.35],
		"a320_gear": [0.55, 0.05],
		"wheel_mat": [0.9, 0.0],
		"a320_glass": [0.08, 0.05],
		"a320_fd_leather": [0.65, 0.0],
		"a320_fd_glare": [0.7, 0.0],
	}
	for k in want:
		if not t.has(k):
			return "missing %s" % k
		if not is_equal_approx(float(t[k].roughness), float(want[k][0])) or not is_equal_approx(float(t[k].metallic), float(want[k][1])):
			return "%s roughness %s metallic %s" % [k, t[k].roughness, t[k].metallic]
	var fuse: Dictionary = t.a320_fuselage
	if not fuse.has("clearcoat") or not is_equal_approx(float(fuse.clearcoat), 0.75):
		return "fuselage clearcoat %s" % fuse.get("clearcoat", "missing")
	if not is_equal_approx(float(fuse.clearcoat_roughness), 0.12):
		return "fuselage clearcoat roughness %s" % fuse.clearcoat_roughness
	if not MaterialFinish.table("c172").is_empty():
		return "c172 must not take the A320 finish table"
	if MaterialFinish.legend_names().has("a320_screen"):
		return "a320_screen is a display, not a window or a legend light"
	return ""


func test_cabin_glow_follows_the_sun() -> String:
	if MaterialFinish.cabin_glow(45.0, false, true) != 0.0:
		return "full sun glow should be 0, got %s" % MaterialFinish.cabin_glow(45.0, false, true)
	if MaterialFinish.cabin_glow(6.0, true, false) != 0.0:
		return "sun above 5 deg should be 0"
	var night := MaterialFinish.cabin_glow(-10.0, false, true)
	if night <= 0.0:
		return "sun down glow should be > 0, got %s" % night
	var parked := MaterialFinish.cabin_glow(-10.0, true, false)
	if parked <= 0.0 or parked >= night:
		return "parked with engines off should be a dimmer positive glow, got %s vs %s" % [parked, night]
	return ""


## The livery pass duplicates the material and swaps albedo. Roughness, metal and clearcoat stay.
func test_albedo_swap_keeps_shading() -> String:
	var src := StandardMaterial3D.new()
	src.resource_name = "a320_fuselage"
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	src.albedo_texture = ImageTexture.create_from_image(img)
	MaterialFinish.restamp(src)
	var img2 := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img2.fill(Color.RED)
	var swapped := ImageTexture.create_from_image(img2)
	var d := src.duplicate() as StandardMaterial3D
	d.albedo_texture = swapped
	d.next_pass = src.next_pass
	MaterialFinish.restamp(d)
	if not is_equal_approx(d.roughness, 0.32) or not is_equal_approx(d.metallic, 0.0):
		return "fuselage shading lost on albedo swap (rough %s metal %s)" % [d.roughness, d.metallic]
	if d.albedo_texture != swapped:
		return "albedo texture was not the swapped one"
	if not d.clearcoat_enabled or not is_equal_approx(d.clearcoat, 0.75) or not is_equal_approx(d.clearcoat_roughness, 0.12):
		return "clearcoat lost on albedo swap"
	var eng := StandardMaterial3D.new()
	eng.resource_name = "a320_engine"
	MaterialFinish.restamp(eng)
	if not is_equal_approx(eng.roughness, 0.45) or not is_equal_approx(eng.metallic, 0.35):
		return "engine shading rough %s metal %s" % [eng.roughness, eng.metallic]
	var tyre := StandardMaterial3D.new()
	tyre.resource_name = "wheel_mat"
	tyre.roughness = 0.55
	MaterialFinish.restamp(tyre)
	if not is_equal_approx(tyre.roughness, 0.55):
		return "restamp must leave wheel_mat alone (C172 tyres share that name)"
	return ""


## bind_maps takes a stand-in texture, so the real AO and panel pngs do not have to exist.
func test_bind_maps_keeps_table_shading() -> String:
	if not MaterialFinish.table("c172").is_empty():
		return "c172 table must stay empty"
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 1.0))
	var tex := ImageTexture.create_from_image(img)
	var alb_img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	alb_img.fill(Color.WHITE)
	var alb := ImageTexture.create_from_image(alb_img)
	var row: Dictionary = MaterialFinish.table("a320")["a320_fuselage"]
	var fuse := StandardMaterial3D.new()
	fuse.resource_name = "a320_fuselage"
	fuse.albedo_texture = alb
	fuse.roughness = float(row.roughness)
	fuse.metallic = float(row.metallic)
	fuse.clearcoat_enabled = true
	fuse.clearcoat = float(row.clearcoat)
	fuse.clearcoat_roughness = float(row.clearcoat_roughness)
	MaterialFinish.bind_maps(fuse, tex)
	if not fuse.ao_enabled or fuse.ao_texture != tex:
		return "fuselage ao missing"
	if not fuse.normal_enabled or fuse.normal_texture != tex:
		return "fuselage normal missing"
	if not is_equal_approx(fuse.ao_light_affect, 0.15) or not is_equal_approx(fuse.normal_scale, 0.5):
		return "fuselage map strength ao %s scale %s" % [fuse.ao_light_affect, fuse.normal_scale]
	if not is_equal_approx(fuse.roughness, float(row.roughness)) or not is_equal_approx(fuse.metallic, float(row.metallic)):
		return "fuselage roughness changed"
	if not fuse.clearcoat_enabled or not is_equal_approx(fuse.clearcoat, float(row.clearcoat)) or not is_equal_approx(fuse.clearcoat_roughness, float(row.clearcoat_roughness)):
		return "fuselage clearcoat changed"
	if fuse.albedo_texture != alb:
		return "albedo texture changed"
	var gear := StandardMaterial3D.new()
	gear.resource_name = "a320_gear"
	gear.roughness = 0.55
	MaterialFinish.bind_maps(gear, tex)
	if not gear.ao_enabled or gear.ao_texture != tex or gear.normal_enabled or gear.normal_texture != null:
		return "gear should take ao only"
	if not is_equal_approx(gear.roughness, 0.55):
		return "gear roughness changed"
	var tyre := StandardMaterial3D.new()
	tyre.resource_name = "wheel_mat"
	tyre.roughness = 0.41
	MaterialFinish.bind_maps(tyre, tex)
	if tyre.ao_enabled or tyre.ao_texture != null or tyre.normal_enabled or tyre.normal_texture != null:
		return "wheel_mat gained maps"
	if not is_equal_approx(tyre.roughness, 0.41):
		return "wheel_mat roughness changed"
	var other := StandardMaterial3D.new()
	other.resource_name = "c172_paint"
	MaterialFinish.bind_maps(other, tex)
	if other.ao_enabled or other.ao_texture != null or other.normal_enabled or other.normal_texture != null:
		return "unlisted material gained maps"
	var legend := StandardMaterial3D.new()
	legend.resource_name = "a320_fd_buttons"
	legend.roughness = 0.8
	MaterialFinish.bind_maps(legend, tex, false)
	if not legend.ao_enabled or legend.ao_texture != tex or legend.normal_enabled or legend.normal_texture != null:
		return "interior legend should take ao only"
	if not is_equal_approx(legend.roughness, 0.8):
		return "interior legend roughness changed"
	var glass := StandardMaterial3D.new()
	glass.resource_name = "a320_glass"
	MaterialFinish.bind_maps(glass, tex, false)
	if glass.ao_enabled or glass.ao_texture != null or glass.normal_texture != null:
		return "interior glass gained maps"
	return ""


## Daylight keeps a floor; night is brighter; off, a dead bus, and any other lamp are dark.
func test_annunciator_follows_the_switch_and_the_bus() -> String:
	var saved := {
		"controls/fcu/ap1": Props.get_v("controls/fcu/ap1", 0),
		"controls/fcu/ap2": Props.get_v("controls/fcu/ap2", 0),
		"controls/autobrake": Props.get_v("controls/autobrake", 0),
	}
	Props.set_v("controls/fcu/ap1", 1)
	Props.set_v("controls/fcu/ap2", 0)
	Props.set_v("controls/autobrake", 2)
	var day := CockpitLamps.energy(CockpitLamps.lit("lamp_ap1"), 0.0, 0.7, true)
	var night := CockpitLamps.energy(CockpitLamps.lit("lamp_ap1"), 1.0, 0.7, true)
	var dead := CockpitLamps.energy(true, 1.0, 0.7, false)
	var other := CockpitLamps.energy(CockpitLamps.lit("lamp_ap2"), 1.0, 0.7, true)
	var unknown := CockpitLamps.energy(CockpitLamps.lit("lamp_fault"), 1.0, 0.7, true)
	var med := CockpitLamps.lit("lamp_autobrake_med")
	var lo := CockpitLamps.lit("lamp_autobrake_lo")
	Props.set_v("controls/fcu/ap1", 0)
	var off := CockpitLamps.energy(CockpitLamps.lit("lamp_ap1"), 1.0, 0.7, true)
	for k in saved:
		Props.set_v(k, saved[k])
	if day < CockpitLamps.LAMP_DAY:
		return "day AP1 should sit on the day floor, got %s" % day
	if night <= day:
		return "night should be brighter than day, %s vs %s" % [night, day]
	if dead != 0.0 or off != 0.0 or other != 0.0 or unknown != 0.0:
		return "dark lamps: dead %s off %s other %s unknown %s" % [dead, off, other, unknown]
	if not med or lo:
		return "autobrake MED should be the only lit step (med %s lo %s)" % [med, lo]
	return ""
