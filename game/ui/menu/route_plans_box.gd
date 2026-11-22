class_name RoutePlansBox
extends HBoxContainer
## The Route step's plan buttons (under the nav log): Save plan… and Load plan… (PlanStore, user://plans/, through the
## RoutePlanDialog modal) and the MSFS flight plan files: Import .PLN… and Export .PLN… (PlanFile / PlanImport, the
## system's file dialog). Loading or importing writes Session.setup (the route, and the departure when the plan starts
## elsewhere: PlanStore.apply) and emits `loaded`; the page repaints and tells the player. Messages go out as `message`.

signal loaded(text: String, warn: bool)
signal message(text: String, warn: bool)

var save_btn: Button
var load_btn: Button
var import_btn: Button
var export_btn: Button
var dialog: RoutePlanDialog  # the open Save / Load modal, or null
var _open_file: FileDialog
var _save_file: FileDialog


func _init() -> void:
	add_theme_constant_override("separation", 4)
	save_btn = _button("Save plan…", "Save this route under a name (Load plan… brings it back)", open_save)
	load_btn = _button("Load plan…", "Load a saved route plan", open_load)
	import_btn = _button("Import .PLN…", "Open a flight plan from Microsoft Flight Simulator or Little Navmap (.pln)", open_import)
	export_btn = _button("Export .PLN…", "Write this route as a flight plan for Microsoft Flight Simulator or Little Navmap (.pln)", open_export)


func _button(t: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.tooltip_text = tip
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_size_override("font_size", 12)

	b.pressed.connect(cb)
	add_child(b)
	return b


## Grey out what needs a route (Save, Export).
func refresh(planned: bool) -> void:
	for b in [save_btn, export_btn]:
		b.disabled = not planned
		b.focus_mode = Control.FOCUS_NONE if b.disabled else Control.FOCUS_ALL


func open_save() -> void:
	_show(RoutePlanDialog.make("save", PlanStore.default_name(Session.setup)))
	dialog.save_named.connect(save_as)


func open_load() -> void:
	_show(RoutePlanDialog.make("load"))
	dialog.load_picked.connect(load_plan)


## Save the current route as `plan_name` and close the dialog (it stays open with the reason on a failure).
func save_as(plan_name: String) -> void:
	var res := PlanStore.save(plan_name, Session.setup)
	if not res.ok:
		if dialog != null:
			dialog.say(str(res.error), true)
		return
	_close()
	message.emit("Plan \"%s\" saved." % plan_name.strip_edges(), false)


func load_plan(key: String) -> void:
	var plan := PlanStore.read(key)
	if plan.is_empty():
		if dialog != null:
			dialog.say("That plan could not be read.", true)
		return
	var res := PlanStore.apply(plan, Session.setup, RouteChecks.db())
	if not res.ok:
		if dialog != null:
			dialog.say(str(res.error), true)
		return
	_close()
	loaded.emit(str(res.text), bool(res.airport_changed))


## A .PLN file's text into the setup: {ok, text}. Errors and notes are in the text.
func import_text(text: String, file_name := "") -> Dictionary:
	var parsed := PlanFile.parse(text)
	if not parsed.ok:
		return {"ok": false, "text": "%s: %s" % [file_name, parsed.error] if file_name != "" else str(parsed.error)}
	var s: Dictionary = Session.setup
	var res := PlanImport.to_route(parsed.plan, RouteChecks.db(), RouteEdit.default_cruise_ft(str(s.get("aircraft", ""))))
	if not res.ok:
		return {"ok": false, "text": str(res.error)}
	var title := str(parsed.plan.title) if str(parsed.plan.title) != "" else file_name
	var app := PlanStore.apply({"name": title, "departure": res.airport, "route": res.route}, s, RouteChecks.db())
	if not app.ok:
		return {"ok": false, "text": str(app.error)}
	var notes: Array = res.notes
	return {"ok": true, "text": " ".join([str(app.text).replace("Plan", "Flight plan")] + notes), "warn": not notes.is_empty() or app.airport_changed}


func open_import() -> void:
	if _open_file == null:
		_open_file = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Open a flight plan (.pln)")
		_open_file.file_selected.connect(_import_file)
	_open_file.popup_centered_ratio(0.6)


func _import_file(path: String) -> void:
	var r := import_text(PlanImport.decode(FileAccess.get_file_as_bytes(path)), path.get_file())
	if r.ok:
		loaded.emit(str(r.text), bool(r.warn))
	else:
		message.emit(str(r.text), true)


## The current route as .PLN text ("" without a route or a known departure).
func export_text() -> String:
	var plan := PlanImport.from_setup(Session.setup, RouteChecks.db())
	return "" if plan.is_empty() else PlanFile.write(plan)


func open_export() -> void:
	if _save_file == null:
		_save_file = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Save the flight plan (.pln)")
		_save_file.file_selected.connect(_export_file)
	_save_file.current_file = PlanStore.file_key(PlanStore.default_name(Session.setup)).to_upper() + ".pln"
	_save_file.popup_centered_ratio(0.6)


func _export_file(path: String) -> void:
	var text := export_text()
	if text == "":
		message.emit("Nothing to export: plan a route from a known airport first.", true)
		return
	if path.get_extension().to_lower() != "pln":
		path += ".pln"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		message.emit("Could not write %s" % path, true)
		return
	f.store_string(text)
	f.close()
	message.emit("Flight plan saved: %s" % path.get_file(), false)


func _file_dialog(m: FileDialog.FileMode, title: String) -> FileDialog:
	var d := FileDialog.new()
	d.file_mode = m
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.title = title
	d.filters = PackedStringArray(["*.pln, *.PLN ; Flight plans"])
	add_child(d)
	return d


## Put the modal over the whole start screen (the nearest ancestor that knows modal_open), else under the top node.
func _show(d: RoutePlanDialog) -> void:
	_close()
	dialog = d
	var host: Node = self
	while not host.has_method("modal_open") and host.get_parent() != null and not host.get_parent() is Window:
		host = host.get_parent()
	host.add_child(d)
	d.closed.connect(func(): dialog = null)


func _close() -> void:
	if dialog != null and is_instance_valid(dialog):
		dialog.close()
	dialog = null
