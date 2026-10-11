class_name LightLogic
extends RefCounted
## Pure aircraft-lighting rules (no nodes), shared by AircraftLights, CockpitLighting,
## world/flight.gd and tests/test_aircraft_lights.gd.

const DUSK_ELEV := 5.0         # sun elevation (deg) below which the night light set is used
const STROBE_PERIOD := 1.2     # s, double flash (C172S wingtip strobes ~50/min)
const STROBE_FLASH := 0.05     # s, each flash
const STROBE_GAP := 0.12       # s, start of the second flash
const BEACON_PERIOD := 1.1     # s, flashing red fin beacon (~55/min)
const BEACON_FLASH := 0.16     # s
const AIRCRAFT_LAYER := 1 << 9  # render layer 10: exterior meshes, lit by the aircraft's own lights
const PANEL_NIGHT_DEFAULT := 0.7


## Light switch positions at a start. kind: "air", "runway" or "stand"; cold = cold & dark.
## Daylight keeps the old default (beacon only).
static func start_state(kind: String, sun_elev_deg: float, agl_ft: float, cold: bool) -> Dictionary:
	var s := {"beacon": true, "nav": false, "strobe": false, "landing": false, "taxi": false, "panel": PANEL_NIGHT_DEFAULT}
	if cold:
		for k in s:
			s[k] = false if k != "panel" else 0.0
		return s
	if sun_elev_deg < DUSK_ELEV:
		s.nav = true
		s.strobe = kind in ["air", "runway"]
		s.landing = kind == "runway" or (kind == "air" and agl_ft < 3000.0)
		s.taxi = kind == "runway"
	return s


## 0 in daylight (sun >= 5 deg) .. 1 at night (sun <= -6 deg).
static func night_factor(sun_elev_deg: float) -> float:
	return clampf((DUSK_ELEV - sun_elev_deg) / 11.0, 0.0, 1.0)


## Strobe intensity 0/1 at time t (double flash).
static func strobe_on(t: float) -> bool:
	var ph := fposmod(t, STROBE_PERIOD)
	return ph < STROBE_FLASH or (ph >= STROBE_GAP and ph < STROBE_GAP + STROBE_FLASH)


## Beacon intensity 0..1 at time t: fast rise, short exponential tail (LED/xenon flash).
static func beacon_level(t: float) -> float:
	var ph := fposmod(t, BEACON_PERIOD)
	if ph < BEACON_FLASH:
		return 1.0
	return exp(-(ph - BEACON_FLASH) * 30.0) if ph < BEACON_FLASH + 0.15 else 0.0


## Brightness of a position light seen from direction `az_deg` (camera azimuth in the
## aircraft's horizontal plane: 0 = ahead, +90 = right, 180 = behind). Sectors per
## FAR 23.1385: left red 0..110 left, right green 0..110 right, tail white 140 aft.
## Off-sector the lens still glints a little (spill) so the light reads from a chase view.
static func nav_sector(which: int, az_deg: float, spill := 0.25) -> float:
	var a := wrapf(az_deg, -180.0, 180.0)
	var inside := 0.0
	match which:
		0: inside = 1.0 - smoothstep(105.0, 115.0, -a) if a <= 0.0 else 1.0 - smoothstep(0.0, 10.0, a)
		1: inside = 1.0 - smoothstep(105.0, 115.0, a) if a >= 0.0 else 1.0 - smoothstep(0.0, 10.0, -a)
		2: inside = smoothstep(105.0, 115.0, absf(a))
	return spill + (1.0 - spill) * inside


## Gauge brightness multiplier of the unshaded 3D panel: 1 in daylight; at night the
## internal lighting follows the PANEL dimmer (a dark panel stays faintly legible).
static func panel_brightness(dim: float, night: float, powered: bool) -> float:
	var lit := 0.12 + (0.9 * clampf(dim, 0.0, 1.0) if powered else 0.0)
	return lerpf(1.0, minf(lit, 1.0), night)


## Light-emitting radio displays: always readable while powered.
static func display_brightness(dim: float, night: float, powered: bool) -> float:
	if not powered:
		return panel_brightness(0.0, night, false)
	return lerpf(1.0, 0.7 + 0.3 * clampf(dim, 0.0, 1.0), night)


## Glareshield flood energy (cabin), 0 in daylight.
static func flood_energy(dim: float, night: float, powered: bool) -> float:
	return 0.45 * clampf(dim, 0.0, 1.0) * night if powered else 0.0


## Sun elevation (deg) now, from the time of day (environment/sun_elev_deg is only
## published by SkyTime once it has run a frame, which is after a flight's first reset).
static func sun_elev_now() -> float:
	if not Props.has("weather/time_h"):
		return Props.get_f("environment/sun_elev_deg", 30.0)
	var sp := SkyTime.sun_position(Props.get_f("weather/time_h"), Props.get_f("weather/day_of_year", 45.0))
	return rad_to_deg(sp.x)
