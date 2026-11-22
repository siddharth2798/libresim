class_name CockpitLamps
extends RefCounted
## Annunciator energy for the A320 faces named lamp_<pivot> in interior.glb.
## Sits beside MaterialFinish.legend_energy: legends are dark in daylight, these lamps
## keep a day floor so an ON light still reads, and get brighter at night with the panel dimmer.
## A face with no row here stays dark (FAULT captions, EXPED, and the overhead buttons the sim has no system for).
## The FCU and EFIS green bars (CockpitBarLamps) show what the autoflight is doing, not the button press: AP1 / AP2
## engaged, A/THR armed or active, LOC / APPR armed or captured (ap/*, systems/autoflight.gd), FD on, LS shown, and
## the one ND option selected (controls/efis/nd_filter 1 CSTR, 2 WPT, 3 VOR.D, 4 NDB, 5 ARPT).

const LAMP_DAY := 0.4  # emission with the sun up, bus powered, switch selected
const BAR_DAY := 1.6  # green bars in daylight: they must read against a sunlit glareshield
const BAR_NIGHT := 0.22  # at night with the dimmer at 0; up to BAR_NIGHT + BAR_DIM at full bright
const BAR_DIM := 0.38

## node name -> [property, value that means selected]
const _ON := {
	"lamp_ap1": ["ap/ap1", 1.0],
	"lamp_ap2": ["ap/ap2", 1.0],
	"lamp_athr": ["ap/athr", 1.0],
	"lamp_loc": ["ap/loc", 1.0],
	"lamp_appr": ["ap/appr", 1.0],
	"lamp_fd_cpt": ["ap/fd", 1.0], "lamp_fd_fo": ["ap/fd", 1.0],
	"lamp_ls_cpt": ["controls/efis/ls", 1.0], "lamp_ls_fo": ["controls/efis/ls", 1.0],
	"lamp_cstr_cpt": ["controls/efis/nd_filter", 1.0], "lamp_cstr_fo": ["controls/efis/nd_filter", 1.0],
	"lamp_wpt_cpt": ["controls/efis/nd_filter", 2.0], "lamp_wpt_fo": ["controls/efis/nd_filter", 2.0],
	"lamp_vord_cpt": ["controls/efis/nd_filter", 3.0], "lamp_vord_fo": ["controls/efis/nd_filter", 3.0],
	"lamp_ndb_cpt": ["controls/efis/nd_filter", 4.0], "lamp_ndb_fo": ["controls/efis/nd_filter", 4.0],
	"lamp_arpt_cpt": ["controls/efis/nd_filter", 5.0], "lamp_arpt_fo": ["controls/efis/nd_filter", 5.0],
	"lamp_apu_master": ["controls/apu_master", 1.0],
	"lamp_apu_start": ["controls/apu_start", 1.0],
	"lamp_wing_anti_ice": ["controls/anti_ice/wing", 1.0],
	"lamp_eng1_anti_ice": ["controls/anti_ice/eng_1", 1.0],
	"lamp_eng2_anti_ice": ["controls/anti_ice/eng_2", 1.0],
	"lamp_autobrake_lo": ["controls/autobrake", 1.0],
	"lamp_autobrake_med": ["controls/autobrake", 2.0],
	"lamp_autobrake_max": ["controls/autobrake", 3.0],
	# overhead ELEC / HYD / FUEL / AIR: an OFF caption lights at 0, an ON caption at 1 (tools/blender/a320_panel_systems.py)
	"lamp_bat1": ["controls/electrical/bat1", 0.0],
	"lamp_bat2": ["controls/electrical/bat2", 0.0],
	"lamp_gen1": ["controls/electrical/gen1", 0.0],
	"lamp_gen2": ["controls/electrical/gen2", 0.0],
	"lamp_apu_gen": ["controls/electrical/apu_gen", 0.0],
	"lamp_ext_pwr": ["controls/electrical/ext_pwr", 1.0],
	"lamp_green_edp": ["controls/hyd/green_edp", 0.0],
	"lamp_yellow_edp": ["controls/hyd/yellow_edp", 0.0],
	"lamp_blue_epump": ["controls/hyd/blue_epump", 0.0],
	"lamp_yellow_epump": ["controls/hyd/yellow_epump", 1.0],
	"lamp_ptu": ["controls/hyd/ptu", 0.0],
	"lamp_fuel_l1": ["controls/fuel/pump_left", 0.0],
	"lamp_fuel_l2": ["controls/fuel/pump_left", 0.0],
	"lamp_fuel_c1": ["controls/fuel/pump_centre", 0.0],
	"lamp_fuel_c2": ["controls/fuel/pump_centre", 0.0],
	"lamp_fuel_r1": ["controls/fuel/pump_right", 0.0],
	"lamp_fuel_r2": ["controls/fuel/pump_right", 0.0],
	"lamp_xfeed": ["controls/fuel/crossfeed", 1.0],
	"lamp_bleed1": ["controls/bleed/eng1", 0.0],
	"lamp_bleed2": ["controls/bleed/eng2", 0.0],
	"lamp_apu_bleed": ["controls/bleed/apu", 1.0],
	"lamp_pack1": ["controls/bleed/pack1", 0.0],
	"lamp_pack2": ["controls/bleed/pack2", 0.0],
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


## The green bars: steady in daylight; at night much lower and set by the panel dimmer, so they do not bloom.
static func bar_energy(night: float, dim: float, powered: bool) -> float:
	if not powered:
		return 0.0
	var n := clampf(night, 0.0, 1.0)
	return lerpf(BAR_DAY, BAR_NIGHT + BAR_DIM * clampf(dim, 0.0, 1.0), n)


static func _num(v) -> float:
	if v == null:
		return 0.0
	if v is bool:
		return 1.0 if v else 0.0
	return float(v)
