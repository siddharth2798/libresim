class_name MapKeys
extends RefCounted
## The keys of the in-flight N map (ui/moving_map.gd) and its hint line. N opens and closes it. While it is open: +/- zoom,
## Space follows the aircraft, O north up / heading up, G fits the route, Backspace clears it (fixed keys), and the
## rebindable "Map: edit route" (KeyBindings map_edit_route, default E, Controls page) turns edit mode on and off.
## The bindings are read again when Props input/bindings_rev changes (the Controls page saved).

const HINT := "Wheel or +/- zoom   ·   drag to pan   ·   click airport = direct-to   ·   Shift+click = add to route"
const EDIT_HINT := "Click: add a point   ·   drag a waypoint: move   ·   drag a leg: insert   ·   right-click: remove   ·   Shift+click airport: destination"

var path := KeyBindings.PATH  # tests point it elsewhere
var _table := {}
var _shifted := {}
var _rev := -1


## What a key press does: "toggle" (N), a map strip button id ("in", "out", "orient", "fit", "clear", "edit"),
## "follow", or "" (not a map key, or the map is closed).
func action(e: InputEvent, open: bool) -> String:
	if not (e is InputEventKey and e.pressed):
		return ""
	var k := e as InputEventKey
	if k.keycode == KEY_N and not k.echo and not k.shift_pressed and not k.ctrl_pressed:
		return "toggle"
	if not open:
		return ""
	if KeyBindings.matches(table(), "map_edit_route", k, _shifted):
		return "" if k.echo else "edit"
	if k.ctrl_pressed or k.meta_pressed:
		return ""
	match k.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: return "in"
		KEY_MINUS, KEY_KP_SUBTRACT: return "out"
		KEY_SPACE: return "follow"
		KEY_O: return "orient"
		KEY_G: return "fit"
		KEY_BACKSPACE: return "clear"
	return ""


## The first key bound to edit mode as text ("E"); "" when it has none.
func edit_key() -> String:
	var slots: Array = table().get("map_edit_route", [])
	return KeyBindings.describe(slots[0]) if not slots.is_empty() else ""


## The map's bottom line when nothing else is said: the gestures of the mode, its edit key and N.
func hint(editing: bool) -> String:
	var k := edit_key()
	if editing:
		return EDIT_HINT + ("   ·   %s: done" % k if k != "" else "")
	return HINT + ("   ·   %s: edit route" % k if k != "" else "") + "   ·   N close"


func table() -> Dictionary:
	var rev := int(Props.get_v("input/bindings_rev", 0))
	if rev != _rev or _table.is_empty():
		_rev = rev
		_table = KeyBindings.load_from(path)
		_shifted = KeyBindings.shifted_keys(_table)
	return _table
