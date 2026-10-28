class_name SD
extends Display
## System display (lower ECAM screen): a page per system, selected with the keys along the bottom
## (click) or Props sd/page ("ENG", "FUEL", "WHEEL", "FCTL"); pages are drawn by sd_pages.gd.
## Writes sd/page; reads the Props listed there.

const PAGES := ["ENG", "FUEL", "WHEEL", "FCTL"]
const NAMES := {"ENG": "ENG", "FUEL": "FUEL", "WHEEL": "WHEEL", "FCTL": "F/CTL"}


func _init() -> void:
	design = Vector2(520, 420)


func _press(id: String, _b: int, _p: Vector2) -> void:
	if id in PAGES:
		Props.set_v("sd/page", id)


func page() -> String:
	var p := str(Props.get_v("sd/page", "ENG"))
	return p if p in PAGES else "ENG"


func _paint() -> void:
	match page():
		"ENG": SdPages.eng(self)
		"FUEL": SdPages.fuel(self)
		"WHEEL": SdPages.wheel(self)
		_: SdPages.flt_ctl(self)
	var sat := Units.k_to_c(Props.get_f("atmosphere/temperature_k", 288.15))
	txt(Vector2(8, 14), "SAT %+d C" % roundi(sat), 14, GREEN)
	for i in PAGES.size():
		var r := Rect2(8 + i * 126, 380, 118, 32)
		var on: bool = PAGES[i] == page()
		fill(r, Color(0.22, 0.26, 0.3) if on else Color(0.12, 0.13, 0.15))
		frame(r, WHITE if on else GREY, 1.5)
		txt(r.get_center(), NAMES[PAGES[i]], 16, WHITE, 0)
		hot(r, PAGES[i])
