class_name FailureRow
extends VBoxContainer
## One failure of the Failures step: a switch to arm it and, while armed, its trigger (segmented: at start / after
## time / altitude / airspeed) with the number the trigger needs (minutes, feet or knots). Reads and writes
## Session.setup.failures through FailuresLogic; `refresh()` repaints from there (after Clear all, a remove button
## elsewhere, another aircraft). Emits `changed` after every edit.

signal changed

var failure_id := ""
var switch: SwitchRow
var trigger: Segmented
var spin: SpinBox
var _detail: HFlowContainer


func setup(id: String, label: String) -> FailureRow:
	failure_id = id
	add_theme_constant_override("separation", 2)
	switch = SwitchRow.new().setup(label)
	switch.toggled.connect(_on_armed)
	add_child(switch)
	_detail = HFlowContainer.new()
	_detail.add_theme_constant_override("h_separation", 10)
	_detail.add_theme_constant_override("v_separation", 6)
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 64)  # under the title, past the switch
	indent.add_theme_constant_override("margin_bottom", 6)
	indent.add_child(_detail)
	add_child(indent)
	trigger = Segmented.new()
	trigger.equal_width = false
	trigger.pad_x = 8  # four labels in a column that has to fit next to the 240 px rail
	trigger.set_options(FailuresLogic.TRIGGERS.map(func(t): return [t[0], t[1], t[2]]))
	trigger.selected.connect(_on_trigger)
	_detail.add_child(trigger)
	spin = SpinBox.new()
	spin.max_value = 20000
	spin.custom_minimum_size = Vector2(120, 0)
	spin.value_changed.connect(_on_value)
	_detail.add_child(spin)
	refresh()
	return self


## Repaint the controls from Session.setup.failures without sending any signal.
func refresh() -> void:
	var f: Dictionary = Session.setup.failures
	var mode := FailuresLogic.mode_of(f, failure_id)
	switch.set_on(mode > 0)
	trigger.select(mode if mode > 0 else null)
	_detail.get_parent().visible = mode > 0
	spin.set_value_no_signal(FailuresLogic.value_of(f, failure_id))
	spin.visible = mode >= 2
	spin.suffix = FailureCatalog.MODE_UNITS[mode] if mode > 0 else ""


func _on_armed(on: bool) -> void:
	FailuresLogic.set_trigger(Session.setup.failures, failure_id, 1 if on else 0)
	refresh()
	changed.emit()


func _on_trigger(mode: Variant) -> void:
	FailuresLogic.set_trigger(Session.setup.failures, failure_id, int(mode))  # the mode's default value
	refresh()
	changed.emit()


func _on_value(v: float) -> void:
	var f: Dictionary = Session.setup.failures
	var mode := FailuresLogic.mode_of(f, failure_id)
	if mode >= 2:
		FailuresLogic.set_trigger(f, failure_id, mode, v)
		changed.emit()
