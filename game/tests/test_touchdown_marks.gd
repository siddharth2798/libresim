extends RefCounted
## Your own tyre marks (world/touchdown_marks.gd): the runway a touchdown lies on and its runway-local mark, the
## per-runway limit, save / load through the "saveable" hook, and a new flight clearing them.

const R27 := {"airport": "VABB", "width": 60.0, "length": 3470.2, "ends": [
	{"ident": "27", "x": -54652.8, "y": 37589.9, "heading_true": 269.37},
	{"ident": "09", "x": -58122.8, "y": 37551.7, "heading_true": 89.37}]}
const R14 := {"airport": "VABB", "width": 45.0, "length": 2870.3, "ends": [
	{"ident": "32", "x": -55064.8, "y": 36660.3, "heading_true": 314.3},
	{"ident": "14", "x": -57119.0, "y": 38665.0, "heading_true": 134.3}]}


## ENU point `along` m from runway r's ends[0] and `across` m right of its centreline (travelling to ends[1]).
func _at(r: Dictionary, along: float, across: float) -> Vector2:
	var a := Vector2(r.ends[0].x, r.ends[0].y)
	var u := (Vector2(r.ends[1].x, r.ends[1].y) - a).normalized()
	return a + u * along + Vector2(u.y, -u.x) * across


func test_touchdown_lands_on_the_right_runway_with_along_across_and_yaw() -> String:
	var p := _at(R27, 380.0, 3.5)
	var hd := deg_to_rad(269.37 + 2.0)  # landing 27, crabbed 2 degrees right
	var m := TouchdownMarks.locate([R14, R27], p.x, p.y, hd, 0.8)
	if m.is_empty() or m.key != "VABB/27":
		return "touchdown 380 m down 27 found on %s" % [m.get("key", "no runway")]
	var v: Vector4 = m.mark
	if absf(v.x - 380.0) > 0.05 or absf(v.y - 3.5) > 0.05:
		return "mark at along %.2f, across %.2f, want 380, 3.5" % [v.x, v.y]
	if absf(rad_to_deg(v.z) - 2.0) > 0.05:
		return "yaw %.2f deg, want 2 (right of the runway direction)" % rad_to_deg(v.z)
	var from_09 := TouchdownMarks.locate([R27], _at(R27, 3000.0, 0.0).x, _at(R27, 3000.0, 0.0).y, deg_to_rad(89.37), 0.5)
	if absf(absf(rad_to_deg(from_09.mark.z)) - 180.0) > 0.1:
		return "landing 09 runs against ends[0] -> ends[1]: yaw should be 180 deg, got %.1f" % rad_to_deg(from_09.mark.z)
	var off := _at(R27, 380.0, 40.0)
	if not TouchdownMarks.locate([R27], off.x, off.y, hd, 0.5).is_empty():
		return "a touchdown on the grass beside the runway leaves no runway mark"
	return ""


func test_a_full_runway_drops_the_oldest_mark() -> String:
	var list := []
	for i in TouchdownMarks.MAX + 3:
		list = TouchdownMarks.appended(list, Vector4(float(i), 0.0, 0.0, 0.5))
	if list.size() != TouchdownMarks.MAX or list[0].x != 3.0 or list[-1].x != float(TouchdownMarks.MAX + 2):
		return "after %d marks: %d kept, oldest %.0f" % [TouchdownMarks.MAX + 3, list.size(), list[0].x]
	return ""


func test_save_load_restores_and_a_new_flight_clears() -> String:
	var tm := TouchdownMarks.new()
	tm.marks = {"VABB/27": [Vector4(380.0, 3.5, 0.03, 0.8), Vector4(392.0, -3.1, 0.03, 0.7)]}
	var saved: Dictionary = JSON.parse_string(JSON.stringify(tm.save_state()))  # through the save file's JSON
	var other := TouchdownMarks.new()
	other.load_state(saved)
	var ok: bool = other.marks.get("VABB/27", []).size() == 2 and other.marks["VABB/27"][1].is_equal_approx(Vector4(392.0, -3.1, 0.03, 0.7))
	var key := tm.save_key()
	var fx := TouchdownFx.new()
	fx.marks = other
	fx.clear()  # flight.gd _reset: a new flight
	var cleared := other.marks.is_empty()
	tm.free()
	other.free()
	fx.free()
	if not ok:
		return "load_state did not restore the saved marks"
	if key != "touchdown_marks":
		return "save key changed: old saves would lose their marks"
	if not cleared:
		return "a new flight (TouchdownFx.clear) must clear the marks"
	return ""


func test_marks_are_drawn_by_the_runway_shader() -> String:
	var src := FileAccess.get_file_as_string("res://world/touchdown_fx.gd")
	if not src.contains("marks.add(") or src.contains("No rubber marks"):
		return "TouchdownFx must leave tyre marks (TouchdownMarks.add)"
	if not FileAccess.get_file_as_string("res://world/runway_wear.gdshaderinc").contains("uniform vec4 marks[32]"):
		return "runway_v2 reads the marks"
	return ""
