class_name AtcTranscript
extends RichTextLabel
## The radio transcript: one coloured line per transmission, newest at the bottom, scrolls to
## follow. Pilot lines blue, the controller green, advisories amber, system notes grey.

const COLORS := {"pilot": "#8cc8ff", "atc": "#9df0b0", "system": "#9aa6b2", "advisory": "#e6c98a"}


func _init() -> void:
	bbcode_enabled = true
	scroll_active = true
	scroll_following = true
	fit_content = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("normal_font_size", 14)
	add_theme_font_size_override("bold_font_size", 14)


## Show the last `max_lines` entries of the log ([{kind, who, text}]).
func show_log(entries: Array, max_lines := 8) -> void:
	var t := ""
	for e in entries.slice(maxi(entries.size() - max_lines, 0)):
		var col: String = COLORS.get(str(e.kind), "#ffffff")
		var body := str(e.text).replace("[", "[lb]")
		if str(e.kind) == "system":
			t += "[color=%s][i]%s[/i][/color]\n" % [col, body]
		else:
			t += "[color=%s][b]%s:[/b] %s[/color]\n" % [col, str(e.who).replace("[", "[lb]"), body]
	text = t.strip_edges(false, true)
	scroll_to_line(maxi(get_line_count() - 1, 0))
