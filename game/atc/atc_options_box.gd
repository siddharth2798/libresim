class_name AtcOptionsBox
extends VBoxContainer
## The ATC part of the Options page: call sign (validated, saved when valid) and the optional
## voice. A self-contained block: ui/menu/options_page.gd adds it with
##     right.add_child(AtcOptionsBox.new())
## and connects `changed` like the other rows. While the menu page is not wired up, the voice
## can also be toggled with V in the in-flight radio menu (ui/atc_panel.gd).

signal changed

var _edit: LineEdit
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(MenuTheme.heading("Radio / ATC"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var l := Label.new()
	l.text = "Call sign"
	l.add_theme_color_override("font_color", MenuTheme.DIM)
	row.add_child(l)
	_edit = LineEdit.new()
	_edit.max_length = 8
	_edit.custom_minimum_size = Vector2(130, 0)
	_edit.text = str(UserOptions.get_v("callsign"))
	_edit.text_changed.connect(_on_text)
	_edit.focus_exited.connect(func():
		if AtcSpeech.normalize_callsign(_edit.text) == "":
			_edit.text = str(UserOptions.get_v("callsign"))
			_status.text = "")
	row.add_child(_edit)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	row.add_child(_status)
	var v := CheckBox.new()
	v.text = "ATC voice (system text-to-speech)"
	v.button_pressed = AtcVoice.enabled()
	var v_note := SpeechNote.new("atc_voice")
	v.toggled.connect(func(on):
		UserOptions.set_v("atc_voice", on)
		v_note.refresh()
		changed.emit())
	add_child(v)
	add_child(v_note)
	add_child(MenuTheme.note("The call sign is used in every radio call, e.g. VT-FSM. The voice speaks the radio transcript with the operating system's voices; it is off by default and has no radio effects yet."))


func _on_text(t: String) -> void:
	var n := AtcSpeech.normalize_callsign(t)
	if n == "":
		_status.text = "not a valid call sign (e.g. VT-FSM, N172SP)"
		return
	_status.text = ""
	UserOptions.set_v("callsign", n)
	changed.emit()
