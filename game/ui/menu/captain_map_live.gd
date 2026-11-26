class_name CaptainMapLive
extends RefCounted
## The live part of the Captain Pack map (ui/menu/captain_map_panel.gd calls step() at 30 Hz while it is open): reads each marker's pad
## numbers, keeps an axis lit for GLOW_S after it last moved, and pushes the glow and the bars to the pictures and lists. Redraws only
## happen when a value changed (the widgets compare).

const GLOW_S := 0.6  # an axis stays lit this long after it last moved
const MOVED := 0.015  # raw change that counts as moving

var hw := {}  # "device/id" -> CaptainMap.hw, filled by the panel's refresh()
var _glow := {}  # "device/id" -> seconds of glow left
var _last := {}  # "device/id" -> last raw axis


## `devs` = device name -> pad id of the connected pack devices.
func step(p: CaptainMapPanel, h: float, devs: Dictionary) -> void:
	for dev in CaptainMap.devices():
		var lit := {}
		for m in CaptainMap.markers(dev):
			var key := "%s/%s" % [dev, m.id]
			var r := CaptainMap.read(m, hw[key], devs.get(dev, -1), p.read_axis, p.read_button)
			var g: float = _glow.get(key, 0.0) - h
			if r.axis != null:
				g = GLOW_S if absf(r.axis - _last.get(key, r.axis)) > MOVED else g
				_last[key] = r.axis
			_glow[key] = maxf(g, 0.0)
			var t := 1.0 if r.down else snappedf(clampf(_glow[key] / GLOW_S, 0.0, 1.0), 0.2)
			lit[m.id] = t
			p.legends[dev].set_live(m.id, t, r.bar)
		p.pictures[dev].set_state(lit, p.pictures[dev].dim, p.pictures[dev].selected)


## Raw value of the selected marker's first axis as text ("" when it has none or its pad is not connected).
func raw_text(selected: Array, devs: Dictionary) -> String:
	var key := "%s/%s" % selected
	return "%.3f" % _last[key] if _last.has(key) and devs.has(selected[0]) else ""
