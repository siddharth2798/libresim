class_name CallsignField
extends VBoxContainer
## The pilot's call sign / registration: a labelled text field bound to Session.setup.callsign (rules in core/callsign.gd).
## The same call sign is painted on the tail and used on the radio. Shared by the Aircraft step and Options > Radio; every
## instance follows the others, and a typed value survives a change of aircraft.
##     var cs := CallsignField.new().setup("Call sign")   # label text, optional
##     parent.add_child(cs)
##   signal callsign_changed(value)  a valid call sign was stored ("" = cleared: the aircraft's own registration again)
##   refresh()   re-read Session.setup and the chosen aircraft (placeholder = its own registration); call it after the aircraft
##               changed. It also runs when the field becomes visible and when another instance stores a value.
##   edit        the LineEdit (tests focus it / type into it).
## Typing: upper-case, A-Z 0-9 and "-", 8 characters at most. Only a valid call sign is stored (per keystroke); a half-typed
## one shows the hint in amber and on Enter / leaving the field the text goes back to the stored value. Empty = untouched =
## the call sign follows the aircraft.

signal callsign_changed(value: String)

const WARN_TEXT := "Needs 3 to 7 letters or digits, one dash allowed, e.g. VT-ABC"

static var _live: Array = []  # instances in the tree, for the sync

var edit: LineEdit
var _label: Label
var _hint: Label
var _label_text := "Call sign"


func setup(label := "Call sign") -> CallsignField:
	_label_text = label
	return self


func _enter_tree() -> void:
	_live.append(self)


func _exit_tree() -> void:
	_live.erase(self)


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_label = Label.new()
	_label.text = _label_text
	_label.add_theme_color_override("font_color", MenuTheme.DIM)
	row.add_child(_label)
	edit = LineEdit.new()
	edit.max_length = Callsign.MAX_CHARS
	edit.custom_minimum_size = Vector2(150, 0)
	edit.clear_button_enabled = true
	edit.add_theme_stylebox_override("normal", MenuTheme.box(Color(1, 1, 1, 0.07), 6, Color(1, 1, 1, 0.30)))  # a visible field on the dark panel
	edit.add_theme_color_override("font_placeholder_color", MenuTheme.DIM)  # the placeholder IS the call sign until one is typed
	edit.text_changed.connect(_on_text)
	edit.text_submitted.connect(func(_t): _revert())
	edit.focus_exited.connect(_revert)
	row.add_child(edit)
	_hint = MenuTheme.note("")
	_hint.add_theme_font_size_override("font_size", 13)
	add_child(_hint)
	visibility_changed.connect(_when_shown)
	refresh()


func _when_shown() -> void:
	if is_visible_in_tree():
		refresh()


func refresh() -> void:
	if edit == null:
		return
	var def := AircraftDef.current()
	var own := Callsign.default_of(def)
	edit.placeholder_text = own
	edit.tooltip_text = "Leave empty for this aircraft's own registration (%s). A call sign you type stays when you change aircraft." % own
	if not edit.has_focus():
		edit.text = Callsign.typed()
	_show_hint(def)


func _show_hint(def: AircraftDef, warn := false) -> void:
	_hint.add_theme_color_override("font_color", MenuTheme.WARN if warn else MenuTheme.DIM)
	if warn:
		_hint.text = WARN_TEXT
		return
	var radio := AtcProfile.radio_callsign(def)  # "" = the registration is also the radio call sign
	_hint.text = "Painted on the tail and used on the radio" if radio == "" else "Painted on the tail. Radio call: \"%s\"." % radio


func _on_text(t: String) -> void:
	var f := Callsign.filter_typing(t)
	if f != t:
		var col := edit.caret_column
		edit.text = f
		edit.caret_column = mini(col, f.length())
	if Callsign.problem(f) != "":
		_show_hint(AircraftDef.current(), true)  # half typed: nothing stored yet
		return
	if not Callsign.store(f):
		return
	_show_hint(AircraftDef.current())
	callsign_changed.emit(Callsign.typed())
	for other in _live:
		if other != self and is_instance_valid(other):
			other.refresh()


## Enter or leaving the field: a text that is not a call sign goes back to the stored one.
func _revert() -> void:
	if Callsign.problem(edit.text) != "":
		edit.text = Callsign.typed()
	_show_hint(AircraftDef.current())
