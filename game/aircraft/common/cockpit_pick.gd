class_name CockpitPick
extends RefCounted
## Picking a cockpit lever (pivot_* driven by aircraft.json cockpit.levers). Glass quads are the caller's
## problem: a screen hit wins, and this ray is only cast when the pointer missed them.
## next_value(drive, map, current, drag_dy) -> the value to write:
##   bool property (current is bool, or a known switch path) -> toggled
##   detent map (more than the two ends, or an integer on a 0/1 pair such as the gear) -> next mapped
##     value, wrapping. drag_dy is ignored.
##   continuous pair (exactly two rows, the ends of a range) -> current slid by drag_dy along that range.
##     Pointer up (negative drag_dy) moves toward the higher end. DRAG_PX covers the whole range.

const DRAG_PX := 140.0
const HIT_PAD := 0.004
const EMPTY_HALF := 0.03


static func next_value(drive: String, map: Array, current: Variant, drag_dy: float) -> Variant:
	if _toggle(drive, current):
		return not bool(current)
	if _drags(drive, map, current):
		return _slide(map, float(current), drag_dy)
	return _step(map, current)


static func drags(drive: String, map: Array, current: Variant) -> bool:
	return _drags(drive, map, current)


static func read_current(drive: String) -> Variant:
	var terms := CockpitLevers.parse_drive(drive)
	if terms.size() != 1:
		return CockpitLevers.read_drive(terms)
	var raw: Variant = Props.get_v(str(terms[0][1]), null)
	return 0.0 if raw == null else raw


static func write_drive(drive: String, value: Variant) -> void:
	var terms := CockpitLevers.parse_drive(drive)
	if terms.is_empty():
		return
	if terms.size() == 1:
		_write_one(str(terms[0][1]), float(terms[0][0]), value)
		return
	if terms.size() == 2 and float(terms[1][0]) < 0.0:
		var v := float(value)
		Props.set_v(str(terms[0][1]), v if v >= 0.0 else 0.0)
		Props.set_v(str(terms[1][1]), 0.0 if v >= 0.0 else -v)
		return
	if terms.size() == 2 and float(terms[1][0]) > 0.0:
		var n := int(round(float(value)))
		Props.set_v(str(terms[0][1]), n >= 1)
		Props.set_v(str(terms[1][1]), n >= 2)


static func commit(item: Dictionary, drag_dy: float = 0.0) -> void:
	var drive := str(item.get("drive", ""))
	if drive == "":
		return
	var map: Array = item.get("map", [])
	write_drive(drive, next_value(drive, map, read_current(drive), drag_dy))


## Vertical drag drives `item`. A stick whose mesh belongs to the roll pivot (the pitch pivot has none)
## sends vertical motion to the parent pitch lever and horizontal motion to roll.
static func apply_motion(item: Dictionary, items: Array, relative: Vector2) -> void:
	var vert := item
	var horiz: Dictionary = {}
	var node := item.get("node") as Node
	if node != null and str(node.name).ends_with("_roll"):
		var parent := node.get_parent()
		if parent != null and str(parent.name).ends_with("_pitch"):
			for other in items:
				if other is Dictionary and (other as Dictionary).get("node") == parent:
					vert = other
					horiz = item
					break
	_slide_item(vert, relative.y)
	if not horiz.is_empty():
		_slide_item(horiz, -relative.x)


## Closest lever under the ray. A pivot is its own meshes (not a nested pivot's) or, with none, a small box
## on the pivot. Equal distances keep the deeper pivot, so a button wins over the lever it sits on.
static func pick(items: Array, from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	var best_d := -1
	for it in items:
		if not it is Dictionary:
			continue
		var item: Dictionary = it
		var node := item.get("node") as Node3D
		if node == null or not node.is_inside_tree():
			continue
		var t := _hit_pivot(node, from, dir)
		if t < 0.0:
			continue
		var depth := _depth(node)
		if t < best_t - 1.0e-4 or (absf(t - best_t) <= 1.0e-4 and depth > best_d):
			best_t = t
			best_d = depth
			best = item
	return best


## LineEdit / TextEdit focus (the key check), the pause screen, or the pointer over a GUI control.
static func gui_blocks(viewport: Viewport) -> bool:
	if Props.get_b("ui/pause_open"):
		return true
	var focus := viewport.gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return true
	var hovered := viewport.gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE


static func _slide_item(item: Dictionary, drag_dy: float) -> void:
	var drive := str(item.get("drive", ""))
	var map: Array = item.get("map", [])
	if drive == "" or not _drags(drive, map, read_current(drive)):
		return
	commit(item, drag_dy)


static func _write_one(path: String, sign: float, value: Variant) -> void:
	if value is bool or (value is int and absf(sign - 1.0) < 1.0e-6):
		Props.set_v(path, value)
	else:
		Props.set_v(path, float(value) / sign if absf(sign) > 1.0e-6 else float(value))


static func _toggle(drive: String, current: Variant) -> bool:
	if drive.contains(" + ") or drive.contains(" - "):
		return false
	if current is bool:
		return true
	return _bool_path(_one_path(drive))


static func _bool_path(path: String) -> bool:
	if path == "":
		return false
	for action in ControlActions.TOGGLES:
		if str(ControlActions.TOGGLES[action]) == path:
			return true
	if path == "controls/apu_start":
		return true
	return path.begins_with("controls/lights/") and path != "controls/lights/panel"


static func _one_path(drive: String) -> String:
	var terms := CockpitLevers.parse_drive(drive)
	return "" if terms.size() != 1 else str(terms[0][1])


static func _drags(drive: String, map: Array, current: Variant) -> bool:
	return not _toggle(drive, current) and map.size() == 2 and not _two_stop(map, current)


## Gear is stored as an int and its map is the two positions. A float on the same shape (speedbrake) is a range.
static func _two_stop(map: Array, current: Variant) -> bool:
	if not (current is int) or map.size() != 2:
		return false
	if not _integral(map[0][0]) or not _integral(map[1][0]):
		return false
	return absf(float(map[1][0]) - float(map[0][0])) <= 1.0 + 1.0e-3


static func _integral(x: Variant) -> bool:
	return absf(float(x) - roundf(float(x))) < 1.0e-3


static func _slide(map: Array, current: float, drag_dy: float) -> float:
	var lo := float(map[0][0])
	var hi := float(map[1][0])
	var v := current - drag_dy * (hi - lo) / DRAG_PX
	return clampf(v, minf(lo, hi), maxf(lo, hi))


static func _step(map: Array, current: Variant) -> Variant:
	if map.is_empty():
		return current
	var x := float(current)
	var nxt := float(map[0][0])
	for row in map:
		if float(row[0]) > x + 1.0e-4:
			nxt = float(row[0])
			break
	if current is int and _integral(nxt):
		return int(round(nxt))
	return nxt


static func _hit_pivot(pivot: Node3D, from: Vector3, dir: Vector3) -> float:
	var meshes := _owned_meshes(pivot)
	if meshes.is_empty():
		var p := pivot.global_position
		var box := AABB(p - Vector3.ONE * EMPTY_HALF, Vector3.ONE * EMPTY_HALF * 2.0)
		return _ray_box(from, dir, box)
	var best := -1.0
	for m in meshes:
		var t := _ray_box(from, dir, _world_box(m as MeshInstance3D))
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


static func _owned_meshes(pivot: Node) -> Array:
	var out: Array = []
	if pivot is MeshInstance3D:
		out.append(pivot)
	for mi in pivot.find_children("*", "MeshInstance3D", true, false):
		if _nearest_pivot(mi) == pivot:
			out.append(mi)
	return out


static func _nearest_pivot(node: Node) -> Node:
	var n := node.get_parent()
	while n != null:
		if str(n.name).begins_with("pivot_"):
			return n
		n = n.get_parent()
	return null


static func _world_box(mi: MeshInstance3D) -> AABB:
	var b := mi.get_aabb()
	var xf := mi.global_transform
	var box := AABB()
	for i in 8:
		var c := Vector3(
			b.position.x if (i & 1) == 0 else b.end.x,
			b.position.y if (i & 2) == 0 else b.end.y,
			b.position.z if (i & 4) == 0 else b.end.z)
		var w: Vector3 = xf * c
		box = AABB(w, Vector3.ZERO) if i == 0 else box.expand(w)
	return box.grow(HIT_PAD)


static func _ray_box(from: Vector3, dir: Vector3, box: AABB) -> float:
	var t0 := 0.0
	var t1 := 1.0e8
	var lo := box.position
	var hi := box.end
	for a in 3:
		var o: float = from[a]
		var d: float = dir[a]
		if absf(d) < 1.0e-8:
			if o < lo[a] or o > hi[a]:
				return -1.0
			continue
		var ta := (lo[a] - o) / d
		var tb := (hi[a] - o) / d
		if ta > tb:
			var s := ta
			ta = tb
			tb = s
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return -1.0
	if t1 < 0.0:
		return -1.0
	return maxf(t0, 0.0)


static func _depth(n: Node) -> int:
	var d := 0
	var p := n.get_parent()
	while p != null:
		d += 1
		p = p.get_parent()
	return d
