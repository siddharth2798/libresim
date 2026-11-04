extends RefCounted
## Layout audit for the start-screen probes (debug_ui_walk.gd, debug_focus.gd): walks a visible control tree and lists what
## does not fit. Pure reading, nothing is changed. Each finding is one line "<path>: <what>".
##   cut      a control wider than the room its container gave it (its minimum width exceeds its width)
##   outside  a focusable control outside the window that no scroll area can bring in (or past a scroll area that cannot scroll that way)
##   hidden   a focusable control with a zero-size rectangle
##   sideways a scroll area whose content is wider than it (the player has to scroll sideways to reach all of it)
##   tall     the start screen's own scroll area (a direct child of the audited root) whose content is taller than it: the whole screen scrolls

static func audit(root: Node, view: Rect2) -> Array[String]:
	var out: Array[String] = []
	_walk(root, view, root, out)
	return out


static func _walk(n: Node, view: Rect2, root: Node, out: Array[String]) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control:
		var c := n as Control
		if c.is_visible_in_tree():
			_check(c, view, root, out)
	for k in n.get_children():
		_walk(k, view, root, out)


static func _check(c: Control, view: Rect2, root: Node, out: Array[String]) -> void:
	if c is ScrollContainer and c.get_child_count() > 0 and c.get_child(0) is Control:
		var sc := c as ScrollContainer
		var need := (sc.get_child(0) as Control).get_combined_minimum_size()
		if sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and need.x > sc.size.x + 1.5:
			out.append("%s: sideways: content needs %.0f px, the area is %.0f" % [_path(c, root), need.x, sc.size.x])
		if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and need.y > sc.size.y + 1.5 and c.get_parent() == root:  # the start screen's own guard scroll
			out.append("%s: tall: content needs %.0f px, the window shows %.0f" % [_path(c, root), need.y, sc.size.y])
	var r := c.get_global_rect()
	var focusable := c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled)
	if c.get_combined_minimum_size().x > c.size.x + 1.5 and c.size.x > 0.0 and not _in_clip_scroll(c, true):
		out.append("%s: cut: needs %.0f px, has %.0f" % [_path(c, root), c.get_combined_minimum_size().x, c.size.x])
	if not focusable:
		return
	if r.size.x < 1.0 or r.size.y < 1.0:
		out.append("%s: hidden: zero-size focusable" % _path(c, root))
		return
	var sc := _scroll_of(c)
	if sc == null:
		if not view.grow(1.5).encloses(r):
			out.append("%s: outside the window (%s vs %s)" % [_path(c, root), r, view])
		return
	var sr := sc.get_global_rect()
	if sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and (r.end.x > sr.end.x + 1.5 or r.position.x < sr.position.x - 1.5):
		out.append("%s: cut off sideways by its scroll area (%s vs %s)" % [_path(c, root), r, sr])
	if sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and (r.end.y > sr.end.y + 1.5 or r.position.y < sr.position.y - 1.5):
		out.append("%s: cut off vertically by its scroll area" % _path(c, root))


## The nearest ScrollContainer above c (null when none).
static func _scroll_of(c: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


## Inside a ScrollContainer whose own content is allowed to be wider than the view (it scrolls sideways).
static func _in_clip_scroll(c: Control, _horizontal: bool) -> bool:
	var sc := _scroll_of(c)
	return sc != null and sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED


static func _path(c: Node, root: Node) -> String:
	var parts: Array[String] = []
	var n: Node = c
	while n != null and n != root and parts.size() < 3:
		var label := n.get_class()
		if n is Button:
			label += "'%s'" % (n as Button).text.strip_edges().left(24)
		elif n is Label:
			label += "'%s'" % (n as Label).text.strip_edges().left(24)
		elif n.get_script() != null:
			label = str(n.get_script().resource_path).get_file().get_basename()
		parts.append(label)
		n = n.get_parent()
	parts.reverse()
	return "/".join(parts)
