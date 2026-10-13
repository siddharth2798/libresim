class_name AtcCard
extends PanelContainer
## The calm card for incoming radio messages: who is speaking, what they said (16 px), and your
## own call and read-back as small muted lines. It lives in the notification stack (ui/notifications.gd
## adopt()), so it never covers anything and fades by itself. What goes into it and for how long is
## in atc/atc_card_logic.gd.

const ACCENT := Color(0.3, 0.85, 0.75)
const TONES := {"ok": Color(0.62, 0.94, 0.7), "warn": Color(1.0, 0.8, 0.42), "dim": Color(0.66, 0.74, 0.82)}
const MUTED := "#8c9db0"

var _head: Label
var _body: RichTextLabel


func _init() -> void:
	add_theme_stylebox_override("panel", Notifications.card_style(ACCENT))
	mouse_filter = MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(vb)
	_head = Label.new()
	_head.add_theme_font_size_override("font_size", 16)
	vb.add_child(_head)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(412, 0)
	_body.mouse_filter = MOUSE_FILTER_IGNORE
	_body.add_theme_font_size_override("normal_font_size", 16)
	_body.add_theme_color_override("default_color", Color(0.9, 0.93, 0.95))
	vb.add_child(_body)


## Show these lines ([{kind, who, text}], oldest first).
func show_lines(lines: Array) -> void:
	var h := AtcCardLogic.head_of(lines)
	_head.text = str(h.text)
	_head.visible = _head.text != ""
	_head.add_theme_color_override("font_color", TONES[h.tone])
	_body.text = markup(lines, str(h.text))


## BBCode of the card body: the controller's words plain, your own lines small and muted.
static func markup(lines: Array, head: String) -> String:
	var out := []
	for l in lines:
		var text := str(l.text).replace("[", "[lb]")
		match str(l.kind):
			"pilot":
				out.append("[font_size=14][color=%s]You: %s[/color][/font_size]" % [MUTED, text])
			"system":
				out.append("[color=#bfd0e0]%s[/color]" % text)
			"advisory":
				out.append("[color=#f0d9a0]%s[/color]" % text)
			_:
				var who := str(l.who)
				out.append(text if who == head else "[b]%s:[/b] %s" % [who, text])
	return "\n".join(out)
