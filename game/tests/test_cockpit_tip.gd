extends Node
## Hovering a cockpit lever or switch names it, the key that moves it, and where it sits.


const Tip = preload("res://ui/cockpit_tip.gd")
const Text = preload("res://ui/cockpit_tip_text.gd")


func test_hover_names_the_control_its_key_and_its_state() -> String:
	var keys := KeyBindings.defaults()
	var tip = Tip.new()
	add_child(tip)
	var err := ""
	var brake: String = tip.text_for("parking_brake", "controls/parking_brake", true, -1, null, keys)
	if brake != "Parking brake\nShift+B\nSet":
		err = "brake [%s]" % brake
	var thrust: String = tip.text_for("thr_l", "controls/throttle_1 - controls/reverse_1", 0.0, -1, null, keys)
	if err == "" and (not thrust.begins_with("Thrust lever 1\n") or not thrust.contains("Alt+PageUp") or not thrust.contains("Num *") or not thrust.ends_with("\nIDLE")):
		err = "thrust [%s]" % thrust
	var flaps: String = tip.text_for("flaps_lever", "controls/flaps", 2, -1, null, keys)
	if err == "" and flaps != "Flaps\nF7 · F6\n1+F":
		err = "flaps [%s]" % flaps
	var tiller: String = tip.text_for("tiller_cpt", "controls/tiller", 0.0, -1, null, keys)
	if err == "" and tiller != "Captain tiller\nTiller axis\nNeutral":
		err = "tiller [%s]" % tiller
	var mode: String = tip.text_for("engine_mode", "controls/engine_mode", 2, -1, null, keys)
	if err == "" and mode != "Engine mode\nCtrl+I\nIGN/START":
		err = "mode [%s]" % mode
	var stick: String = tip.text_for("sidestick_cpt_pitch", "controls/pitch", 0.5, -1, null, keys)
	if err == "" and stick != "Captain sidestick\n↑ · ↓\nNose up 50%":
		err = "stick [%s]" % stick
	var bat: String = tip.text_for("", "", null, 0, true, keys)
	if err == "" and bat != "Battery\nShift+M\nOn":
		err = "battery [%s]" % bat
	var miss: String = tip.text_for("", "", null, -1, null, keys)
	if err == "" and miss != "":
		err = "miss [%s]" % miss
	var glass: Dictionary = Text.choice("glass", Vector2.ZERO, Rect2(), 14, "parking_brake")
	if err == "" and (str(glass.lever) != "" or int(glass.switch) != -1):
		err = "glass %s" % glass
	var row := Rect2(0, 100, 140, 40)
	var cell: Dictionary = Text.choice("switches", Vector2(5, 120), row, 14, "parking_brake")
	if err == "" and (int(cell.switch) != 0 or str(cell.lever) != ""):
		err = "cell %s" % cell
	if err == "" and Text.switch_index(Vector2(5, 10), row, 14) != -1:
		err = "outside the row should hide the note"
	var lever: Dictionary = Text.choice("none", Vector2.ZERO, Rect2(), 14, "thr_l")
	if err == "" and str(lever.lever) != "thr_l":
		err = "lever %s" % lever
	tip.present(brake)
	if err == "" and (tip.shown() != brake or tip.blocks_clicks()):
		err = "popup [%s] blocks %s" % [tip.shown(), tip.blocks_clicks()]
	tip.present("")
	if err == "" and tip.shown() != "":
		err = "hidden [%s]" % tip.shown()
	tip.free()
	return err
