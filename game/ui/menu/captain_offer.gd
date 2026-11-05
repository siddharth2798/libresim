class_name CaptainOffer
extends Control
## "Thrustmaster Captain Pack found" modal on the start screen (ui/menu/captain_watch.gd shows it): a dim backdrop and a
## centred panel offering the calibrated profile with three answers, "Use the Captain Pack profile" (focused first),
## "Not now" (asks again next time) and "Don't ask again". Esc = Not now. Tab and the arrows stay inside the three
## buttons; while it is open it takes every key. Built like FlyConfirm (MenuTheme tokens only).
## "use" writes the table through CaptainDetect.apply_profile (the same code as the Controls page's reset button) to
## `bindings_path` and stores "applied"; "never" stores "declined"; "later" stores nothing. Then `chosen` fires with
## "use" | "later" | "never"; the caller frees the node.

signal chosen(what: String)

const BODY := "Use its calibrated profile for the A320 and the C172? You can change it any time on the Controls page: Joystick & gamepad > Reset: Airbus Captain Pack."
const LINUX_NOTE := "Linux numbering is not verified for this hardware."

var bindings_path := CaptainDetect.bindings_path  # where "use" saves; tests point it at a scratch file
var use_btn: Button
var later_btn: Button
var never_btn: Button
var body_label: Label
var _done := false


## The body text; the running OS adds the Linux line.
static func body_text(os_name: String) -> String:
	return BODY + ("\n" + LINUX_NOTE if os_name == "Linux" else "")


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP  # the screen behind cannot be clicked
	name = "CaptainOffer"
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.035, 0.05, 0.075, 0.97), 12, Color(MenuTheme.ACCENT, 0.85), 24.0))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = "Thrustmaster Captain Pack found"
	title.add_theme_font_size_override("font_size", MenuTheme.SIZE_TITLE)
	title.add_theme_color_override("font_color", MenuTheme.ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	body_label = Label.new()
	body_label.text = body_text(OS.get_name())
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body_label)
	use_btn = _button("Use the Captain Pack profile", true)
	use_btn.pressed.connect(_answer.bind("use"))
	v.add_child(use_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	later_btn = _button("Not now", false)
	later_btn.pressed.connect(_answer.bind("later"))
	row.add_child(later_btn)
	never_btn = _button("Don't ask again", false)
	never_btn.pressed.connect(_answer.bind("never"))
	row.add_child(never_btn)
	v.add_child(MenuTheme.note("Not now asks again next time. Don't ask again stops this offer."))
	FlyConfirm.trap_focus([use_btn, later_btn, never_btn])
	use_btn.grab_focus.call_deferred()


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", MenuTheme.SIZE_BIG)
	MenuTheme.style_primary(b, primary)
	return b


func _answer(what: String) -> void:
	if _done:
		return
	_done = true
	if what == "use":
		CaptainDetect.apply_profile(bindings_path)
	elif what == "never":
		CaptainDetect.set_state(CaptainDetect.DECLINED)
	chosen.emit(what)


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_answer("later")


func _unhandled_key_input(_e: InputEvent) -> void:
	if is_visible_in_tree():
		get_viewport().set_input_as_handled()  # steps, Ctrl+Enter and the like stay behind the dialog
