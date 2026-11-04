class_name ControlsHeader
extends RefCounted
## The two extras beside the Controls page's tab bar: "Controls for" (a Segmented of the installed aircraft) and the search
## box. Built here so controls_page.gd stays short; the page connects the callbacks. Nothing is stored in the setup.


## Adds the extras to `tabs` and returns {switch: Segmented or null (one aircraft only), search: LineEdit}.
## `current` is the aircraft id to light; `on_aircraft(id)` and `on_search(text)` are called on a change.
static func add(tabs: MenuTabs, current: String, on_aircraft: Callable, on_search: Callable) -> Dictionary:
	var out := {"switch": null}
	var ids := AircraftDef.list_ids()
	if ids.size() > 1:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		var l := Label.new()
		l.text = "Controls for"
		l.add_theme_color_override("font_color", MenuTheme.DIM)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(l)
		var sw := Segmented.new()
		sw.equal_width = false
		sw.set_options(ids.map(func(id): return [id, aircraft_name(id)]), current)
		sw.selected.connect(func(id): on_aircraft.call(str(id)))
		box.add_child(sw)
		tabs.add_extra(box)
		out.switch = sw
	var search := LineEdit.new()
	search.placeholder_text = "Search actions"
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(190, 36)
	search.tooltip_text = "Type to show only the matching actions (name or key). Ctrl+F focuses this box."
	search.text_changed.connect(on_search)
	tabs.add_extra(search)
	out.search = search
	return out


static func aircraft_name(id: String) -> String:
	var def := AircraftDef.load_def(id)
	return str(def.data.get("short_name", id)) if def != null else id


## The note a tab shows when no row matches (hidden until then).
static func no_match_note() -> Label:
	var l := MenuTheme.note("%s: no action matches. Clear the search box to see them all." % ControlsFilter.NO_MATCH)
	l.visible = false
	return l
