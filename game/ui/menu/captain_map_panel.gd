class_name CaptainMapPanel
extends Control
## "Captain Pack map": a full-window helper over the Controls page (opened by captain_map_link.gd). Two photos of the Thrustmaster TCA
## Captain Pack X, Airbus Edition with a numbered marker on every key, lever and switch, and beside each what it does for the chosen
## aircraft ("not used on <aircraft>" when that aircraft lacks the action). It shows the saved joystick table, the one the Controls page
## edits. Choose action (captain_map_picker.gd) binds the selected control at once; Clear, Invert, Bind and Reset to the profile
## (captain_map_actions.gd); Identify (captain_map_identify_ui.gd) selects the control you press and can teach unknown numbers.
## Polls the pads at 30 Hz while open, nothing otherwise: close frees the node. Esc closes. The pack never drives the menu.

signal closed

const TICK_HZ := 30.0
const STACK_BELOW := 1000.0  # UI units of window width under which the two devices are stacked (the page scrolls)
const COMPACT_BELOW := 600.0  # UI units of window height under which the note and hint are dropped

var page: Object  # the Controls page (table, aircraft, Bind, save); null = standalone (saves to save_path)
var table := {}  # the binding table; empty = the page's, else the saved file's
var controls: AircraftControls  # the chosen aircraft; null = the page's, else the current flight's
var save_path := ""  # standalone saves; default CaptainDetect.bindings_path
var read_axis := func(pad: int, axis: int) -> float: return Input.get_joy_axis(pad, axis)  # tests swap these
var read_button := func(pad: int, button: int) -> bool: return Input.is_joy_button_pressed(pad, button)
var pictures := {}  # device -> CaptainMapPicture
var legends := {}  # device -> CaptainMapLegend
var picker: CaptainMapPicker
var present := false
var preview := false  # no pack and the table is not the profile: shows the profile's defaults, read only
var selected := ["", ""]  # [device, marker id]
var sel_part := ""
var waiting := false  # a Bind waits for the control
var armed := false  # Reset waits for its second press
var identifying := false
var saved := {}  # the table that is written (== table unless preview)
var ident := CaptainIdentify.new()
var ident_event := {}
var ident_parts: Array = []  # [[device, marker, part]] behind ident_pick
# widgets, built by CaptainMapView
var main: VBoxContainer
var stack: VBoxContainer
var cols: BoxContainer
var aircraft_switch: Segmented
var status: Label
var note: Label
var detail: Label
var msg: Label
var part_pick: OptionButton
var choose_btn: Button
var bind_btn: Button
var clear_btn: Button
var invert_btn: CheckButton
var identify_btn: Button
var reset_btn: Button
var close_btn: Button
var ident_row: HBoxContainer
var ident_label: Label
var ident_pick: OptionButton
var ident_save: Button
var live := CaptainMapLive.new()
var _tick := TickRate.new(TICK_HZ)
var _raw := ""


## Adds the panel to its own top layer of `host`'s tree and returns it (close() frees both).
static func open(host: Node, page_node: Object = null, panel_table := {}, panel_controls: AircraftControls = null) -> CaptainMapPanel:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var p := CaptainMapPanel.new()
	p.page = page_node
	p.table = panel_table
	p.controls = panel_controls
	layer.add_child(p)
	host.get_tree().root.add_child(layer)
	return p


func _ready() -> void:
	name = "CaptainMapPanel"
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	theme = MenuTheme.make()
	present = CaptainDetect.present(CaptainDetect.connected_pads())
	if page != null and table.is_empty():
		table = page.get("table")
	if page != null and controls == null:
		controls = page.get("controls")
	if table.is_empty():
		table = InputBindings.load_from(CaptainDetect.bindings_path)
	if controls == null:
		controls = AircraftControls.current()
	saved = table
	preview = not present and not CaptainDetect.applied(table)
	if preview:
		table = InputBindings.defaults(InputProfiles.CAPTAIN_PACK)
	CaptainMapView.build(self)
	_fit_layout()
	if page != null and page.has_signal("changed"):
		page.connect("changed", refresh)
	CaptainMapView.wire_focus(self)
	refresh()
	close_btn.grab_focus.call_deferred()


func aircraft_name() -> String:
	return ControlsHeader.aircraft_name(controls.id) if controls.id != "" else "this aircraft"


func say(text: String, warn := false) -> void:
	msg.text = text
	msg.add_theme_color_override("font_color", MenuTheme.WARN if warn else MenuTheme.OK)


func set_aircraft(id: String) -> void:
	var def := AircraftDef.load_def(id) if AircraftDef.list_ids().has(id) else null
	if def == null:
		return
	controls = AircraftControls.for_def(def)
	if aircraft_switch != null:
		aircraft_switch.select(id)
	refresh()


## Re-reads the table: legend texts, dim and unsure markers, tooltips, the header, the detail strip.
func refresh() -> void:
	waiting = false
	var pads := CaptainDetect.connected_pads()
	var unsure_n := 0
	var have := []
	var miss := []
	for dev in CaptainMap.devices():
		var dim := {}
		var unsure := {}
		(have if CaptainMap.pad_id(dev, pads) >= 0 else miss).append(dev)
		for m in CaptainMap.markers(dev):
			live.hw["%s/%s" % [dev, m.id]] = CaptainMap.hw(dev, m)
			var d := CaptainMap.describe(CaptainMap.actions_for(dev, m, table, pads, controls), aircraft_name())
			var bad := CaptainMap.confidence(dev, m) == "unconfirmed"
			var tip := "%s: %s%s" % [m.get("label", m.id), d.text, "  (number not confirmed)" if bad else ""]
			legends[dev].set_text(m.id, d.text, d.unbound or d.unused, tip, bad)
			pictures[dev].tips[m.id] = tip
			dim[m.id] = d.unbound or d.unused
			unsure[m.id] = bad
			unsure_n += int(bad)
		pictures[dev].set_state(pictures[dev].lit, dim, pictures[dev].selected)
		pictures[dev].set_unsure(unsure)
	var st := CaptainMapText.status(have, miss)
	status.text = st.text
	status.add_theme_color_override("font_color", MenuTheme.OK if st.good else MenuTheme.WARN)
	note.text = CaptainMapText.note(preview, CaptainDetect.applied(table), aircraft_name(), unsure_n)
	reset_btn.text = "Press again to confirm" if armed else ("Load the Airbus Captain Pack profile" if preview else "Reset to the Airbus Captain Pack profile")
	_show_detail()


func select(dev: String, id: String, part := "") -> void:
	var m := CaptainMap.marker(dev, id)
	if m.is_empty():
		return
	selected = [dev, id]
	sel_part = part if part != "" else str(m.parts[0].id)
	for d in legends:
		legends[d].select(id if d == dev else "")
		pictures[d].set_state(pictures[d].lit, pictures[d].dim, id if d == dev else "")
	part_pick.clear()
	for i in m.parts.size():
		part_pick.add_item(str(m.parts[i].label))
		if m.parts[i].id == sel_part:
			part_pick.select(i)
	_show_detail()


func pick_part(idx: int) -> void:
	sel_part = str(CaptainMap.marker(selected[0], selected[1]).parts[idx].id)
	_show_detail()


## {marker, part, e (pad numbers), acts (what the table binds to it for this aircraft)} of the selected part, or {}.
func current() -> Dictionary:
	var m := CaptainMap.marker(selected[0], selected[1])
	for p in m.get("parts", []):
		if p.id == sel_part:
			var e := CaptainMap.effective(selected[0], m, p)
			return {"marker": m, "part": p, "e": e, "acts": CaptainMap.part_actions(selected[0], m, p, table, CaptainDetect.connected_pads(), controls)}
	return {}


## The first action of this aircraft bound to the selected part (what Bind and Invert act on), or "".
func bind_target() -> String:
	var c := current()
	return "" if c.is_empty() or c.acts.now.is_empty() else str(c.acts.now[0])


func _show_detail() -> void:
	var c := current()
	part_pick.visible = not c.is_empty() and c.marker.parts.size() > 1
	for b in [choose_btn, bind_btn, clear_btn]:
		b.disabled = true
	invert_btn.visible = false
	if c.is_empty():
		detail.text = "Select a marker or a row for its details, then Choose action to assign it."
		return
	var conf := CaptainMap.part_conf(selected[0], c.marker, c.part)
	var src := str(CaptainMap.data().get("sources", {}).get(str(c.part.get("src", "none")), ""))
	detail.text = CaptainMapText.detail(c.marker, c.part, c.e, c.acts, aircraft_name(), _raw, conf, src)
	var known: bool = CaptainAssign.kind_of(c.e) != ""
	var tgt := bind_target()
	choose_btn.disabled = preview or not known
	choose_btn.tooltip_text = "Load the profile first (this is only a preview)" if preview else ("Press it with Identify on to learn its number" if not known else "")
	bind_btn.disabled = page == null or preview or tgt == "" or waiting
	bind_btn.text = "Bind: %s" % CaptainMap.action_name(tgt) if tgt != "" else "Bind"
	clear_btn.disabled = preview or c.acts.now.is_empty()
	invert_btn.visible = tgt != "" and bool(c.part.get("latching", false)) and CaptainAssign.has_invert(tgt)
	if invert_btn.visible:
		invert_btn.set_pressed_no_signal(bool(table[tgt].get("invert", false)))


# The buttons: what they do is in captain_map_actions.gd and captain_map_identify_ui.gd.
func open_picker() -> void: CaptainMapActions.open_picker(self)
func close_picker() -> void: CaptainMapActions.close_picker(self)
func assign(action: String) -> void: CaptainMapActions.assign(self, action)
func clear_selected() -> void: CaptainMapActions.clear_selected(self)
func set_invert(on: bool) -> void: CaptainMapActions.set_invert(self, on)
func start_bind() -> void: CaptainMapActions.start_bind(self)
func reset_profile() -> void: CaptainMapActions.reset_profile(self)
func set_identify(on: bool) -> void: CaptainMapIdentifyUi.set_on(self, on)
func save_identified() -> void: CaptainMapIdentifyUi.save(self)


## device name -> pad id of the connected pack devices.
func devices() -> Dictionary: return CaptainMap.connected(CaptainDetect.connected_pads())


func _process(dt: float) -> void:
	var h := _tick.step(dt)
	if h <= 0.0:
		return
	if waiting and page != null and str(page.get("_capture")) == "":
		waiting = false  # timed out (a success refreshes through `changed`)
		_show_detail()
	var devs := devices()
	live.step(self, h, devs)
	if identifying:
		for ev in ident.poll(devs, read_axis, read_button):
			CaptainMapIdentifyUi.event(self, ev)
	var raw := live.raw_text(selected, devs)
	if raw != _raw:
		_raw = raw
		_show_detail()


func close() -> void:
	if waiting and page != null:
		page.call("_cancel_capture")
	closed.emit()
	var p := get_parent()
	if p is CanvasLayer:
		p.queue_free()
	else:
		queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and cols != null:
		_fit_layout()


## Narrow window: the devices stack and the page scrolls; short window: the note and the hint go.
func _fit_layout() -> void:
	cols.vertical = size.x < STACK_BELOW
	CaptainMapView.fit(self, size.y < COMPACT_BELOW)


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		if picker != null:
			return  # the picker backs out first
		get_viewport().set_input_as_handled()
		if waiting and page != null:
			page.call("_cancel_capture")
			waiting = false
			_show_detail()
		else:
			close()
	elif _is_pack_event(e):
		get_viewport().set_input_as_handled()  # the pack only lights markers here, it never presses a focused button


func _is_pack_event(e: InputEvent) -> bool:
	if not (e is InputEventJoypadButton or e is InputEventJoypadMotion):
		return false
	var pad := [{"id": e.device, "name": Input.get_joy_name(e.device)}]
	return CaptainMap.devices().any(func(d): return CaptainMap.pad_id(d, pad) >= 0)


func _unhandled_key_input(_e: InputEvent) -> void:
	if is_visible_in_tree():
		get_viewport().set_input_as_handled()  # flight hotkeys and J behind the panel stay quiet
