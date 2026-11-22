extends VBoxContainer
## The pause screen's "Edit route" page (ui/pause_pages.gd): the Route step's editor (ui/menu/route_page.gd in its live
## mode: map, nav log with the fuel line, vertical profile, destination, arrival runway, cruise altitude, auto-route and
## the typed route) on the route ahead of the aircraft. Its first point is the present position (PPOS), the start of
## the active leg (RouteLive). Nothing changes in the flight until Apply (RouteLive.commit; then the flight resumes);
## Cancel (or Esc) drops the edits and goes back to the pause screen's home page. Not here, as they are for before the
## flight: the departure, saved plans and .PLN files, and where an air start begins.

signal closed  # Apply: the pause screen resumes the flight
signal back  # Cancel: the pause screen shows its home page

const PAGE := "res://ui/menu/route_page.gd"

var page: Control  # route_page.gd, live mode
var apply_btn: Button
var cancel_btn: Button
var status: Label
var _sp := {}  # RouteLive.split the page started from
var _dirty := false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	status = MenuTheme.note("")
	status.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(status)
	cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.tooltip_text = "Drop these edits and go back (Esc)"
	cancel_btn.custom_minimum_size = Vector2(110, 38)
	cancel_btn.pressed.connect(cancel)
	bar.add_child(cancel_btn)
	apply_btn = Button.new()
	apply_btn.text = "Apply and resume"
	apply_btn.tooltip_text = "Fly this route: the GPS (and the A320's NAV) follow it at once"
	apply_btn.custom_minimum_size = Vector2(170, 38)
	MenuTheme.style_primary(apply_btn)
	apply_btn.pressed.connect(apply)
	bar.add_child(apply_btn)
	open()


## Start again from the flight as it is now (every time the page is shown): the route ahead, from the present position.
func open() -> void:
	if not is_inside_tree():
		return
	var d := RouteEdit.db()
	_sp = RouteLive.split(Session.setup, d)
	var live := RouteLive.edit_setup(Session.setup, _sp.route, RouteLive.here())
	if page == null:
		page = HBoxContainer.new()
		page.set_script(load(PAGE))
		page.size_flags_vertical = SIZE_EXPAND_FILL
		page.set("live", live)
		page.set("taken", _sp.passed)
		page.connect("changed", _on_changed)
		add_child(page)
	else:
		page.set("live", live)
		page.set("taken", _sp.passed)
		page.set("selected", -1)
		page.call("_refresh", true)
	page.map.aircraft = {"pos": RouteLive.here(), "hdg": Props.get_f("fdm/heading_rad")}
	_dirty = false
	_show_status()


func _on_changed() -> void:
	_dirty = true
	_show_status()


func _show_status() -> void:
	var n := (_sp.passed as Array).size()
	var done := "" if n == 0 else "  %d waypoint%s already flown %s kept." % [n, "" if n == 1 else "s", "is" if n == 1 else "are"]
	status.text = ("Not applied yet: Apply to fly it." if _dirty else "The route ahead, from the aircraft's present position.") + done


## The edited route ahead into the flight (Session.setup.route, GPS, route waypoints, ATC destination, MCDU), resume.
func apply() -> void:
	var ahead := RouteEdit.route_of(page.get("live"))
	RouteLive.commit(_sp, ahead, RouteEdit.db(), RouteLive.airliner())
	RouteLive.clear_ppos()
	_dirty = false
	closed.emit()


func cancel() -> void:
	RouteLive.clear_ppos()
	open()
	back.emit()


func _exit_tree() -> void:
	RouteLive.clear_ppos()
