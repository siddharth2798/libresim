class_name Airway
extends RefCounted
## Expand a published airway between two fixes. `airways` is ident ->
## {fixes: Array, direction: "both"|"forward"|"back"} from airways.json.
## A token is an airway when it contains a digit, is in that dictionary, and
## sits between two idents. Direction follows the published fix order.
## The autopilot does not grow a new mode: NAV flies the fixes this inserts.

const NOT_ON := "NOT ON AIRWAY"
const WRONG_WAY := "AIRWAY DIRECTION"
const AMBIGUOUS := "AMBIGUOUS"


static func expand(parts: Array, airways: Dictionary) -> Dictionary:
	var out: Array = []
	var i := 0
	while i < parts.size():
		var tok := str(parts[i]).strip_edges().to_upper()
		var aw: Variant = airways.get(tok)
		if _designator(tok) and typeof(aw) == TYPE_DICTIONARY and not out.is_empty() and i + 1 < parts.size():
			var exit := str(parts[i + 1]).strip_edges().to_upper()
			if _designator(exit) and airways.has(exit):
				out.append(tok)
				i += 1
				continue
			var mid: Variant = _between(aw, str(out.back()), exit)
			if typeof(mid) == TYPE_STRING:
				return {"ok": false, "error": mid, "parts": []}
			for id in mid:
				out.append(id)
			i += 2
		else:
			out.append(tok)
			i += 1
	return {"ok": true, "error": "", "parts": out}


static func _designator(tok: String) -> bool:
	for ch in tok:
		if ch >= "0" and ch <= "9":
			return true
	return false


static func _between(aw: Dictionary, entry: String, exit: String) -> Variant:
	var fixes: Array = aw.get("fixes", [])
	var a := _at(fixes, entry)
	var b := _at(fixes, exit)
	if a == -2 or b == -2:
		return AMBIGUOUS
	if a < 0 or b < 0 or a == b:
		return NOT_ON
	var forward := b > a
	var way := str(aw.get("direction", "both"))
	if (way == "forward" and not forward) or (way == "back" and forward):
		return WRONG_WAY
	var step := 1 if forward else -1
	var mid: Array = []
	var k := a + step
	while k != b + step:
		mid.append(str(fixes[k]))
		k += step
	return mid


static func _at(fixes: Array, ident: String) -> int:
	var found := -1
	for i in fixes.size():
		if str(fixes[i]) != ident:
			continue
		if found >= 0:
			return -2
		found = i
	return found
