extends VBoxContainer
## One screen of the start menu: a prompt line, a glass panel holding the page(s) in a
## scroll area (small windows scroll instead of pushing buttons off-screen), and a fixed
## bottom bar: Back on the left, a summary line, and the primary action on the right.
## Used on its own for Training, Controls, Options and Saved flights, and as the base of
## start_flow.gd (Free flight). Pages are the ui/menu/*_page.gd scripts (make_page).

signal back_pressed
signal primary_pressed

var prompt: Label
var summary: Label
var back_btn: Button
var primary_btn: Button
var footer: HBoxContainer  # the bottom bar's row (start_flow.gd adds its Fly now button)
var pages: Array[Control] = []
var _stack: MarginContainer


## A page script instance: every ui/menu/*_page.gd extends HBoxContainer.
static func make_page(path: String) -> Control:
	var p := HBoxContainer.new()
	p.set_script(load(path))
	p.size_flags_vertical = SIZE_EXPAND_FILL
	return p


func _init() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 20)
	add_child(prompt)
	var content := PanelContainer.new()
	content.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(content)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_stack = MarginContainer.new()
	_stack.size_flags_horizontal = SIZE_EXPAND_FILL
	_stack.size_flags_vertical = SIZE_EXPAND_FILL
	_stack.add_theme_constant_override("margin_right", 12)
	scroll.add_child(_stack)
	var bar := PanelContainer.new()
	add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	footer = hb
	bar.add_child(hb)
	back_btn = Button.new()
	back_btn.text = "◀  Back"
	back_btn.custom_minimum_size = Vector2(120, 56)
	back_btn.pressed.connect(go_back)
	hb.add_child(back_btn)
	summary = Label.new()
	summary.size_flags_horizontal = SIZE_EXPAND_FILL
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(summary)
	primary_btn = Button.new()
	primary_btn.custom_minimum_size = Vector2(260, 56)
	primary_btn.add_theme_font_size_override("font_size", 22)
	primary_btn.visible = false
	primary_btn.pressed.connect(on_primary)
	hb.add_child(primary_btn)
	MenuTheme.style_primary(primary_btn)


func add_page(p: Control) -> void:
	_stack.add_child(p)
	pages.append(p)


func show_page(i: int) -> void:
	for k in pages.size():
		pages[k].visible = k == i


## Show the primary (filled) button with this label; "" hides it.
func set_primary(text: String) -> void:
	primary_btn.visible = text != ""
	primary_btn.text = text


## Back button / Esc. Overridden by start_flow.gd to step back first.
func go_back() -> void:
	back_pressed.emit()


## Primary button / Ctrl+Enter. Overridden by start_flow.gd to step forward first.
func on_primary() -> void:
	primary_pressed.emit()
