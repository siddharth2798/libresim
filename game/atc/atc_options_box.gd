class_name AtcOptionsBox
extends VBoxContainer
## The ATC part of the Options page: call sign (a CallsignField, ui/menu/callsign_field.gd: Session.setup.callsign,
## shared with the Aircraft step), radio assist (UserOptions radio_assist, on by default) and the optional voice. A self-contained block: the Radio / ATC tab of
## ui/menu/options_page.gd adds it with `AtcOptionsBox.new()` and connects `changed` like the other rows. The voice can also be toggled with V in the open
## in-flight radio (ui/atc_panel.gd).

signal changed


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(MenuTheme.heading("Radio / ATC"))
	add_child(CallsignField.new().setup("Call sign"))  # the same field as on the Aircraft step: one value, both stay in sync
	var a := OptionRows.switch("Radio assist (tunes COM1 for you, suggests the next call)", "radio_assist", func(_on): changed.emit())
	add_child(a)
	add_child(MenuTheme.note("Assist on: a call tunes COM1 to the right unit by itself and the radio bar suggests what to call next. Off: you tune COM1 yourself, as in a real aircraft; nothing is suggested."))
	var v_note := SpeechNote.new("atc_voice")
	var v := OptionRows.switch("ATC voice (system text-to-speech)", "atc_voice", func(_on):
		v_note.refresh()
		changed.emit())
	add_child(v)
	add_child(v_note)
	add_child(MenuTheme.note("The call sign is used in every radio call, e.g. VT-LBR. The voice speaks the radio transcript with the operating system's voices; it is off by default and has no radio effects yet."))
