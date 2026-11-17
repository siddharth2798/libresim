class_name ScreenLayout
extends RefCounted
## The player's Custom outside-view layout (Options > Screen layout, ui/menu/screen_layout_tab.gd) and the
## flight-data bar's place and size.
## Pieces come from the aircraft's panel.json "pieces" catalog ({id: {label, items, anchor, height, on}}).
## A placed piece is {on, x, y, h}: top-left as a fraction of the screen, height as a fraction of the screen
## height; the width follows the piece's shape. The bar is {x (centre), y (top), scale}, the same for every aircraft.
## Stored in user://ui.cfg: [layout_<aircraft id>] pieces, [hud] bar, [panel] layout_name. The panel overlay
## (ui/panel_overlay.gd) shows the pieces as the "Custom" layout and ui/hud.gd places the bar. Props
## ui/layout_rev changes on every save, so a flight under the pause screen follows at once.

const MINIMAP := "minimap"
const REF := Vector2(1920.0, 1080.0)  # the screen the anchors are laid out on for the defaults
const MIN_H := 0.05
const MAX_H := 0.9
const HUD_W := 0.34  # bar size on the reference screen at scale 1, as fractions of it
const HUD_H := 0.068
const HUD_MIN := 0.6
const HUD_MAX := 2.0
const HUD_DEFAULT := {"x": 0.5, "y": 0.009, "scale": 1.0}

static var cfg_path := "user://ui.cfg"  # tests point it at a throw-away file


## [{id, label, items, anchor, height, on}] in the catalog's order ([] if the aircraft has none).
static func catalog(def: AircraftDef) -> Array:
	var out := []
	var raw: Dictionary = def.json("panel") if def else {}
	var pieces: Dictionary = raw.get("pieces", {})
	for id in pieces:
		var p: Dictionary = pieces[id]
		out.append({"id": str(id), "label": str(p.get("label", id)), "items": p.get("items", []),
			"anchor": str(p.get("anchor", "bl")), "height": float(p.get("height", 0.3)), "on": bool(p.get("on", false))})
	return out


## Panel-pixel rect of a set of items on this aircraft's panel (the union, grown 6 px; empty if none).
static func region(def: AircraftDef, items: Array) -> Rect2:
	var r := InstrumentPanel.rects_of(InstrumentPanel.normalize(def.json("panel") if def else {}))
	var out := Rect2()
	var first := true
	for n in items:
		if r.has(n):
			out = r[n] if first else out.merge(r[n])
			first = false
	return Rect2() if first else out.grow(6)


## Width / height of a piece: 1 for the mini-map, else its panel region's.
static func aspect(def: AircraftDef, items: Array) -> float:
	if items == [MINIMAP]:
		return 1.0
	var reg := region(def, items)
	return reg.size.x / reg.size.y if reg.size.y > 0.0 else 1.0


## Top-left of a w x h box at a layout anchor on a vs screen (px).
static func anchor_pos(anchor: String, w: float, h: float, vs: Vector2) -> Vector2:
	match anchor:
		"bl": return Vector2(8, vs.y - h - 8)
		"br": return Vector2(vs.x - w - 8, vs.y - h - 8)
		"bc": return Vector2((vs.x - w) * 0.5, vs.y - h)
		"tr": return Vector2(vs.x - w - 8, 30)
		"tl": return Vector2(8, 30)
		"rc": return Vector2(vs.x - w - 8, (vs.y - h) * 0.5)
	return Vector2.ZERO


## Screen rect (px) of a placed piece on a vs screen: kept whole and on screen.
static func rect_px(p: Dictionary, asp: float, vs: Vector2) -> Rect2:
	var h: float = clampf(float(p.h), MIN_H, MAX_H) * vs.y
	var w := h * asp
	if w > vs.x:
		w = vs.x
		h = w / asp
	var pos := Vector2(float(p.x) * vs.x, float(p.y) * vs.y)
	return Rect2(pos.clamp(Vector2.ZERO, (vs - Vector2(w, h)).max(Vector2.ZERO)), Vector2(w, h))


## The catalog's own placement (anchors on the reference screen): id -> {on, x, y, h}.
static func defaults(def: AircraftDef) -> Dictionary:
	var out := {}
	for c in catalog(def):
		var h: float = c.height * REF.y
		var w := h * aspect(def, c.items)
		var pos := anchor_pos(c.anchor, w, h, REF) / REF
		out[c.id] = {"on": c.on, "x": pos.x, "y": pos.y, "h": c.height}
	return out


## The Custom layout of this aircraft: the defaults with the player's saved pieces over them.
static func load_pieces(def: AircraftDef) -> Dictionary:
	var out := defaults(def)
	var cf := ConfigFile.new()
	if def == null or cf.load(cfg_path) != OK:
		return out
	var saved = cf.get_value("layout_" + def.id, "pieces", {})
	if saved is Dictionary:
		for id in saved:
			if out.has(id) and saved[id] is Dictionary:
				for k in ["on", "x", "y", "h"]:
					if saved[id].has(k):
						out[id][k] = saved[id][k]
	return out


static func save_pieces(def: AircraftDef, pieces: Dictionary, bump_rev := true) -> void:
	_write(func(cf: ConfigFile): cf.set_value("layout_" + def.id, "pieces", pieces.duplicate(true)), bump_rev)


## Forget the player's Custom layout of this aircraft (back to the catalog defaults).
static func reset(def: AircraftDef) -> void:
	_write(func(cf: ConfigFile):
		if cf.has_section("layout_" + def.id):
			cf.erase_section("layout_" + def.id), true)


static func hud() -> Dictionary:
	var out := HUD_DEFAULT.duplicate()
	var cf := ConfigFile.new()
	if cf.load(cfg_path) == OK:
		for k in out:
			out[k] = float(cf.get_value("hud", k, out[k]))
	out.scale = clampf(out.scale, HUD_MIN, HUD_MAX)
	return out


static func save_hud(d: Dictionary) -> void:
	_write(func(cf: ConfigFile):
		for k in HUD_DEFAULT:
			cf.set_value("hud", k, float(d.get(k, HUD_DEFAULT[k]))), true)


static func reset_hud() -> void:
	_write(func(cf: ConfigFile):
		if cf.has_section("hud"):
			cf.erase_section("hud"), true)


## Bar rect on a vs screen (px) for a bar of natural size `bar` (scale 1).
static func hud_rect(d: Dictionary, bar: Vector2, vs: Vector2) -> Rect2:
	var sz := bar * float(d.scale)
	var pos := Vector2(float(d.x) * vs.x - sz.x * 0.5, float(d.y) * vs.y)
	return Rect2(pos.clamp(Vector2.ZERO, (vs - sz).max(Vector2.ZERO)), sz)


## Outside views switch to the Custom layout (the panel overlay picks it up through ui/layout_rev).
static func use_custom() -> void:
	_write(func(cf: ConfigFile): cf.set_value("panel", "layout_name", "Custom"), true)


static func layout_name(default: String) -> String:
	var cf := ConfigFile.new()
	if cf.load(cfg_path) != OK:
		return default
	return str(cf.get_value("panel", "layout_name", default))


static func _write(edit: Callable, bump_rev: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(cfg_path)
	edit.call(cf)
	cf.save(cfg_path)
	if bump_rev:
		Props.set_v("ui/layout_rev", int(Props.get_v("ui/layout_rev", 0)) + 1)
