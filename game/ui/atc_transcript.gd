class_name AtcTranscript
extends RichTextLabel
## The radio history: one line per transmission, newest at the bottom, scrolls to follow (mouse
## wheel or the arrow keys while the history is open). Controller green, radio notes grey, advisories
## amber; your own calls small and muted blue-grey.

const COLORS := {"pilot": "#8fa9c4", "atc": "#9df0b0", "system": "#aab8c6", "advisory": "#e6c98a"}
const MAX_LINES := 30


func _init() -> void:
	bbcode_enabled = true
	scroll_active = true
	scroll_following = true
	fit_content = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("normal_font_size", 15)
	add_theme_font_size_override("bold_font_size", 15)
	add_theme_font_size_override("italics_font_size", 15)
	add_theme_constant_override("line_separation", 3)


## Show the last `max_lines` entries of the log ([{kind, who, text}]).
func show_log(entries: Array, max_lines := MAX_LINES) -> void:
	var t := ""
	for e in entries.slice(maxi(entries.size() - max_lines, 0)):
		var col: String = COLORS.get(str(e.kind), "#ffffff")
		var body := str(e.text).replace("[", "[lb]")
		match str(e.kind):
			"system":
				t += "[color=%s][i]%s[/i][/color]\n" % [col, body]
			"pilot":
				t += "[font_size=14][color=%s]%s: %s[/color][/font_size]\n" % [col, str(e.who).replace("[", "[lb]"), body]
			_:
				t += "[color=%s][b]%s:[/b] %s[/color]\n" % [col, str(e.who).replace("[", "[lb]"), body]
	text = t.strip_edges(false, true)
	scroll_to_line(maxi(get_line_count() - 1, 0))


## Scroll by `lines` (negative = up).
func scroll_lines(lines: int) -> void:
	var bar := get_v_scroll_bar()
	bar.value = clampf(bar.value + float(lines) * 20.0, 0.0, bar.max_value)
