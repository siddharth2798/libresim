class_name SpeechNote
extends Label
## One calm line under a voice checkbox on the Options page, shown only when that voice option is
## on and the system has no text-to-speech voice (core/speech_service.gd). Call refresh() after
## the checkbox changes; while the probe is still running the label checks again by itself.

var option_key := ""


func _init(key: String) -> void:
	option_key = key
	text = SpeechService.MISSING_NOTE
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	add_theme_font_size_override("font_size", 14)
	visible = false


func _ready() -> void:
	refresh()


func refresh() -> void:
	var on := bool(UserOptions.get_v(option_key))
	if on:
		SpeechService.request()
	visible = on and SpeechService.status() == SpeechService.Status.NONE
	set_process(on and SpeechService.status() == SpeechService.Status.PENDING)


func _process(_dt: float) -> void:
	refresh()
