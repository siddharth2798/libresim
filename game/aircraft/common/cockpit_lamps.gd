class_name CockpitLamps
extends RefCounted
## Annunciator energy for the A320 faces named lamp_<pivot> in interior.glb.
## Sits beside MaterialFinish.legend_energy: legends are dark in daylight, these lamps
## keep a day floor so an ON light still reads, and get brighter at night with the panel dimmer.
## A face with no row here stays dark (FAULT captions, and every unkeyed overhead button).

const LAMP_DAY := 0.4  # emission with the sun up, bus powered, switch selected

## node name -> [property, value that means selected]
const _ON := {
	"lamp_ap1": ["controls/fcu/ap1", 1.0],
	"lamp_ap2": ["controls/fcu/ap2", 1.0],
	"lamp_athr": ["controls/fcu/athr", 1.0],
	"lamp_loc": ["controls/fcu/loc", 1.0],
	"lamp_appr": ["controls/fcu/appr", 1.0],
	"lamp_apu_master": ["controls/apu_master", 1.0],
	"lamp_apu_start": ["controls/apu_start", 1.0],
	"lamp_wing_anti_ice": ["controls/anti_ice/wing", 1.0],
	"lamp_eng1_anti_ice": ["controls/anti_ice/eng_1", 1.0],
	"lamp_eng2_anti_ice": ["controls/anti_ice/eng_2", 1.0],
	"lamp_autobrake_lo": ["controls/autobrake", 1.0],
	"lamp_autobrake_med": ["controls/autobrake", 2.0],
	"lamp_autobrake_max": ["controls/autobrake", 3.0],
}


static func lit(node_name: String) -> bool:
	var row: Array = _ON.get(node_name, [])
	if row.is_empty():
		return false
	return absf(_num(Props.get_v(row[0], 0.0)) - float(row[1])) < 0.05


## 0 when the function is off or the bus is dead. Daylight stays at LAMP_DAY; night adds the panel dimmer.
static func energy(on: bool, night: float, dim: float, powered: bool) -> float:
	if not on or not powered:
		return 0.0
	var n := clampf(night, 0.0, 1.0)
	return LAMP_DAY + n * (0.35 + 0.85 * clampf(dim, 0.0, 1.0))


static func _num(v) -> float:
	if v == null:
		return 0.0
	if v is bool:
		return 1.0 if v else 0.0
	return float(v)
