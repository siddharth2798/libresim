class_name PfdIls
extends RefCounted
## The ILS part of the PFD (ui/displays/pfd.gd), shown while the EFIS LS button is on (controls/efis/ls, default on) and
## an ILS is received (avionics/nav{2,1}: kind "ILS", valid; NAV2 first): the localizer scale under the attitude sphere,
## the glide slope scale on its right, and at the bottom left the ident, the frequency (controls/nav<n>/freq_mhz, the
## tuned one) and the DME distance, as on the A320. Deviations are avionics/nav<n>/cdi_raw and gs_raw (1 = 2 dots, the
## scale end; + = fly right / up). Beyond the scale the diamond stops at the end and only its inner half shows.
## An ILS the FMGC auto-tuned (avionics/ils_autotune.gd) shows its ident and frequency before it is received (tuned_labels).
## Pure helpers (source, diamond, diamond_points, labels) are what the tests check; draw() paints with them.

const DOT_PX := 36.0  # px per dot: two dots each side
const HALF_PX := 9.0  # half the diamond's width


## The NAV receiver whose ILS the PFD shows (2 or 1), 0 for none (LS off, or no ILS received).
static func source() -> int:
	if not Props.get_b("controls/efis/ls", true):
		return 0
	for n in [2, 1]:
		var b := "avionics/nav%d/" % n
		if str(Props.get_v(b + "kind", "")) == "ILS" and Props.get_b(b + "valid"):
			return n
	return 0


## Where the diamond goes for deviation `dev` (1 = scale end): {at (-1..1, along the scale), half (beyond the scale)}.
static func diamond(dev: float) -> Dictionary:
	return {"at": clampf(dev, -1.0, 1.0), "half": absf(dev) > 1.0}


## The diamond's polygon on a scale through `mid` along unit `axis` (+ deviation side), DOT_PX * 2 to each end. Beyond
## the scale: the half on the scale side of the end mark (a triangle pointing back to the middle).
static func diamond_points(mid: Vector2, axis: Vector2, dev: float) -> PackedVector2Array:
	var d := diamond(dev)
	var c: Vector2 = mid + axis * float(d.at) * DOT_PX * 2.0
	var across := Vector2(-axis.y, axis.x) * HALF_PX
	var along := axis * HALF_PX
	if d.half:
		var inward := -along * signf(dev)
		return PackedVector2Array([c + across, c + inward, c - across])
	return PackedVector2Array([c - along, c + across, c + along, c - across])


## The bottom-left lines for receiver `n`: ident, frequency ("109.50"), DME ("12.4NM", whole miles from 20 NM;
## left out without DME).
static func labels(n: int) -> Array:
	var b := "avionics/nav%d/" % n
	var out := [str(Props.get_v(b + "ident", "ILS")), "%.2f" % Props.get_f("controls/nav%d/freq_mhz" % n)]
	var dme := Props.get_f(b + "dme_nm", -1.0)
	if dme >= 0.0:
		out.append("%.1fNM" % dme if dme < 20.0 else "%dNM" % roundi(dme))
	return out


## An ILS the FMGC tuned (avionics/ils_auto, avionics/ils_autotune.gd) that is not received yet: its ident and frequency,
## as soon as it is tuned (LS on); [] otherwise. The scales and the DME come with the signal.
static func tuned_labels() -> Array:
	if not Props.get_b("controls/efis/ls", true) or not Props.get_b("avionics/ils_auto/active"):
		return []
	return [str(Props.get_v("avionics/ils_auto/ident", "")), "%.2f" % Props.get_f("avionics/ils_auto/mhz")]


## Deviation of receiver `n`, unclamped when the radio publishes it (`*_raw`), else the clamped needle.
static func dev(n: int, what: String) -> float:
	var b := "avionics/nav%d/" % n
	return Props.get_f(b + what + "_raw", Props.get_f(b + what))


## Paint the scales and labels on display `d` around the sphere rect `z`.
static func draw(d: Display, z: Rect2) -> void:
	var n := source()
	if n == 0:
		var t := tuned_labels()
		for i in t.size():
			d.txt(Vector2(z.position.x + 6, z.end.y - 56 + i * 18), str(t[i]), 16, Display.MAGENTA)
		return
	var c := z.get_center()
	var y := z.end.y - 12.0
	for k in [-2, -1, 1, 2]:
		d.dot(Vector2(c.x + k * DOT_PX, y), 3.5, Display.WHITE)
	d.line(Vector2(c.x, y - 7), Vector2(c.x, y + 7), Display.AMBER, 2.0)
	d.poly(diamond_points(Vector2(c.x, y), Vector2.RIGHT, dev(n, "cdi")), Display.MAGENTA)
	if Props.get_b("avionics/nav%d/gs_valid" % n):
		var x := z.end.x - 12.0
		for k in [-2, -1, 1, 2]:
			d.dot(Vector2(x, c.y + k * DOT_PX), 3.5, Display.WHITE)
		d.line(Vector2(x - 7, c.y), Vector2(x + 7, c.y), Display.AMBER, 2.0)
		d.poly(diamond_points(Vector2(x, c.y), Vector2.UP, dev(n, "gs")), Display.MAGENTA)
	var lines := labels(n)
	for i in lines.size():
		d.txt(Vector2(z.position.x + 6, z.end.y - 56 + i * 18), str(lines[i]), 16, Display.MAGENTA)
