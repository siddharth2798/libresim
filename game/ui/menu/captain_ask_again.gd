class_name CaptainAskAgain
extends Button
## Tiny link under the pad list on the Controls page's joystick tab: "Offer the Captain Pack profile again". Shown only
## when a Captain Pack is connected and the offer was answered "Don't ask again" (core/captain_detect.gd, UserOptions
## "captain_pack" = "declined"). Pressing it clears that answer, so the start screen offers the profile at the next start.

const TEXT := "Offer the Captain Pack profile again"


func _ready() -> void:
	flat = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	size_flags_horizontal = SIZE_SHRINK_BEGIN
	add_theme_color_override("font_color", MenuTheme.ACCENT)
	pressed.connect(_ask_again)
	Input.joy_connection_changed.connect(func(_d, _c): refresh())
	refresh()


func refresh() -> void:
	visible = CaptainDetect.state() == CaptainDetect.DECLINED and CaptainDetect.present(CaptainDetect.connected_pads())
	disabled = false
	text = TEXT


func _ask_again() -> void:
	CaptainDetect.set_state("")
	text = "Done: libresim will offer it again the next time it starts."
	disabled = true
