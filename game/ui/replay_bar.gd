class_name ReplayBar
extends Control
## Instant-replay controls (systems/replay.gd). R toggles replay (from 60 s back, or
## the start of the recording if shorter). In replay: Space play/pause, Left/Right
## seek -/+5 s, [ / ] slower / faster. A bottom bar with timeline, play/pause, speeds,
## "Take control" and "Exit replay", and a big REPLAY tag top-left.

const BACK_S := 60.0
const SEEK_S := 5.0

const MIN_W := 760.0  # narrowest the bar may get before it moves above the panel

@export var replay_path: NodePath = ^"../../Replay"
@export var panel_path: NodePath = ^"../Panel"  # 2-D instrument panel pieces to keep clear of

var replay: Replay
var _tag: Label
var _note: Label  # how the replayed flight ended, when it crashed
var _bar: PanelContainer
var _play: Button
var _slider: HSlider
var _time: Label
var _speeds := {}  # speed -> Button
var _dragging := false
var _was_playing := false


func _ready() -> void:
	if replay == null:
		replay = get_node_or_null(replay_path)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_build()
	visible = false
	if replay:
		replay.started.connect(func(): visible = true)
		replay.stopped.connect(func(_took: bool): visible = false)


func _build() -> void:
	_tag = Label.new()
	_tag.add_theme_font_size_override("font_size", 44)
	_tag.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_tag.add_theme_color_override("font_outline_color", Color.BLACK)
	_tag.add_theme_constant_override("outline_size", 8)
	_tag.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	_tag.grow_horizontal = GROW_DIRECTION_BOTH
	_tag.offset_top = 34  # below the camera-name label
	add_child(_tag)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 20)
	_note.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	_note.add_theme_color_override("font_outline_color", Color.BLACK)
	_note.add_theme_constant_override("outline_size", 6)
	_note.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	_note.grow_horizontal = GROW_DIRECTION_BOTH
	_note.offset_top = 92
	_note.visible = false
	add_child(_note)

	_bar = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_bar.add_theme_stylebox_override("panel", sb)
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_bar.add_child(row)

	_play = _button(row, "Pause", func(): replay.toggle_play())
	_play.custom_minimum_size.x = 70
	_slider = HSlider.new()
	_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	_slider.size_flags_vertical = SIZE_SHRINK_CENTER
	_slider.step = 0.0
	_slider.focus_mode = FOCUS_NONE
	_slider.custom_minimum_size.x = 120
	_slider.value_changed.connect(_on_slider)
	_slider.drag_started.connect(_on_drag_start)
	_slider.drag_ended.connect(_on_drag_end)
	row.add_child(_slider)
	_time = Label.new()
	_time.custom_minimum_size.x = 96
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_time)
	for s in Replay.SPEEDS:
		var label := ("%sx" % s).replace("0.", ".") if s < 1.0 else "%dx" % int(s)
		_speeds[s] = _button(row, label, func(): replay.set_speed(s))
		_speeds[s].toggle_mode = true
	row.add_child(VSeparator.new())
	_button(row, "Take control", func(): replay.take_control())
	_button(row, "Exit replay", func(): replay.stop_replay())


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE  # Space must not "click" the last button
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _unhandled_key_input(e: InputEvent) -> void:
	if replay == null or not e.pressed:
		return
	var k: Key = e.keycode
	if not replay.active:
		if k == KEY_R and not e.echo and not e.ctrl_pressed and not Props.get_b("view/free_cam"):
			if replay.start_replay(BACK_S):
				get_viewport().set_input_as_handled()
		return
	match k:
		KEY_R:
			if not e.echo:
				replay.stop_replay()
		KEY_SPACE:
			if not e.echo:
				replay.toggle_play()
		KEY_LEFT:
			replay.seek_relative(-SEEK_S)
		KEY_RIGHT:
			replay.seek_relative(SEEK_S)
		KEY_BRACKETLEFT:
			if not e.echo:
				replay.step_speed(-1)
		KEY_BRACKETRIGHT:
			if not e.echo:
				replay.step_speed(1)
		_:
			return
	get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	if not visible or replay == null or not replay.active:
		return
	_layout()
	var total := replay.total()
	_slider.max_value = maxf(total, 0.01)
	if not _dragging:
		_slider.set_value_no_signal(replay.elapsed())
	_time.text = "%s / %s" % [_mmss(replay.elapsed()), _mmss(total)]
	_play.text = "Pause" if replay.playing else "Play"
	for s in _speeds:
		_speeds[s].set_pressed_no_signal(is_equal_approx(s, replay.speed))
	var sp := ("%sx" % replay.speed) if replay.speed < 1.0 else "%dx" % int(replay.speed)
	_tag.text = "REPLAY  %s%s" % [sp, "" if replay.playing else "  II"]
	_note.visible = Props.get_b("damage/crashed")  # the flight being replayed ended in a crash: say how
	_note.text = "Ends in a crash: " + str(Props.get_v("damage/reason", ""))


## Bottom of the screen in the widest gap between the 2-D panel pieces that sit at
## the bottom; if no gap is wide enough, just above the tallest of them.
func _layout() -> void:
	var vs := get_viewport_rect().size
	var h := _bar.get_combined_minimum_size().y
	var xs: Array = [[0.0, 0.0], [vs.x, vs.x]]  # occupied [x0, x1] spans along the bottom
	var top := vs.y
	var panel := get_node_or_null(panel_path) as Control
	if panel and panel.is_visible_in_tree():
		for c in panel.get_children():
			if c is Control and c.visible:
				var r: Rect2 = c.get_global_rect()
				if r.end.y > vs.y - h - 24.0 and r.size.x > 0.0:
					xs.append([r.position.x, r.end.x])
					top = minf(top, r.position.y)
	xs.sort_custom(func(a, b): return a[0] < b[0])
	var best := Vector2.ZERO  # widest free span (x0, x1)
	var reach := 0.0
	for s in xs:
		if s[0] - reach > best.y - best.x:
			best = Vector2(reach, s[0])
		reach = maxf(reach, s[1])
	var rect := Rect2(16.0, vs.y - h - 12.0, vs.x - 32.0, h)
	if best.y - best.x - 24.0 >= MIN_W:
		rect = Rect2(best.x + 12.0, vs.y - h - 12.0, best.y - best.x - 24.0, h)
	elif top < vs.y:
		rect.position.y = top - h - 8.0
	_bar.position = rect.position
	_bar.size = rect.size


func _on_slider(v: float) -> void:
	if replay and replay.active:
		replay.seek(replay.buffer.start_time() + v)


func _on_drag_start() -> void:
	_dragging = true
	_was_playing = replay.playing
	replay.set_playing(false)


func _on_drag_end(_changed: bool) -> void:
	_dragging = false
	if _was_playing:
		replay.set_playing(true)


static func _mmss(s: float) -> String:
	var i := int(maxf(s, 0.0))
	return "%d:%02d" % [i / 60, i % 60]
