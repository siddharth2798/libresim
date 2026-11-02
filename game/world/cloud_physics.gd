class_name CloudPhysics
extends RefCounted
## Clouds as physics at the aircraft: owned by Weather, which calls update() every physics tick and adds
## the returned wind / turbulence terms. Publishes (all at the aircraft position):
##   environment/ac_cloud_density 0..1, ac_in_cloud, cloud_base_m, cloud_top_m (AMSL), cloud_kind,
##   turbulence_scale (x the Dryden sigma), thermal_mps (+ up), storm_intensity 0..1, storm_core,
##   storm_shear_mps (wind the storm cell adds).
## Reads weather/cloud_*, precip, convection, storms, turbulence, temp_c, aloft wind, environment/sun_elev_deg
## and environment/cloud_drift (SkyTime: the advection of the visual cloud layer, so structure matches).
## environment/in_cloud stays the camera's (fog, visuals). Details: docs/USAGE.md "Weather physics".

const LAND_EVERY := 0.5  # s between land-class lookups under the aircraft

var _t := 0.0  # storm clock (s)
var _land := 1.0
var _land_timer := 0.0


## Conditions from the weather Props (and the sun) as the pure functions want them.
static func conditions() -> Dictionary:
	var cover := Props.get_f("weather/cloud_cover")
	var conv := Props.get_f("weather/convection")
	var elev := _sun_elev()
	var shade := 1.0 - 0.7 * smoothstep(0.6, 1.0, cover)  # a thick deck cuts the sun's heating
	var warm := clampf(0.6 + 0.4 * (Props.get_f("weather/temp_c", 30.0) - 10.0) / 20.0, 0.5, 1.1)
	var aloft := Weather._from_dir_to_ned(Props.get_f("weather/aloft_dir_deg"), Props.get_f("weather/aloft_kt") * Units.KT)
	var precip := Props.get_f("weather/precip")
	var storms := Props.get_f("weather/storms")
	return {
		"cover": cover, "base_m": Units.ft_to_m(Props.get_f("weather/cloud_base_ft", 4500.0)),
		"convection": conv, "storms": storms, "precip": precip, "land": 1.0,
		"heat": CloudConvection.heating(elev) * shade * warm,
		"kind": CloudField.kind(cover, precip, conv, storms, elev, Props.get_f("weather/turbulence")),
		"drift": Props.get_v("environment/cloud_drift", Vector2.ZERO),
		"wind_en": Vector2(aloft.y, aloft.x),  # east, north
	}


static func _sun_elev() -> float:
	if Props.has("environment/sun_elev_deg"):
		return Props.get_f("environment/sun_elev_deg")
	var sp := SkyTime.sun_position(Props.get_f("weather/time_h", 10.0), Props.get_f("weather/day_of_year", 45.0))
	return rad_to_deg(sp.x)


## Cloud, convection and storm state at ENU p (agl m above ground) for conditions c and storm clock t_s:
## {density, in_cloud, base_m, top_m, kind, turb_scale, turb_floor, thermal, wind (NED added to the
## air mass), storm_intensity, storm_core, shear}.
static func evaluate(c: Dictionary, p: Vector3, agl: float, t_s: float) -> Dictionary:
	var base: float = c.base_m
	var cover: float = c.cover
	var drift: Vector2 = c.drift
	var dens := CloudField.density(p, base, cover, drift)
	var near := CloudField.proximity(p, base, cover, drift) if dens < CloudField.IN_CLOUD and cover > 0.0 else 0.0
	var kind_name: String = c.kind
	var under := CloudField.under_base(p.z, base, kind_name, float(c.convection) * float(c.heat))
	var scale := CloudField.turbulence_scale(kind_name, dens, near, under)
	var th := CloudConvection.thermal(p, agl, c, dens)
	var st := {"wind": Vector3.ZERO, "intensity": 0.0, "core": false, "shear": 0.0}
	if kind_name == CloudField.CUMULONIMBUS and float(c.storms) > 0.0:
		st = CloudStorm.sample(p, agl, t_s, c.wind_en, float(c.storms), base)
	var wind: Vector3 = st.wind + Vector3(0.0, 0.0, -th)
	return {
		"density": dens, "in_cloud": dens > CloudField.IN_CLOUD, "base_m": base, "top_m": CloudField.top_m(base),
		"kind": kind_name, "turb_scale": maxf(scale, 1.0 + 3.0 * st.intensity), "turb_floor": 3.0 * st.intensity,
		"thermal": th, "wind": wind, "storm_intensity": st.intensity, "storm_core": st.core, "shear": st.shear,
	}


## Called by Weather each physics tick: evaluate at the aircraft, publish, return the result.
func update(dt: float, pos: Vector3, agl: float, terrain: TerrainQuadtree) -> Dictionary:
	_t += dt
	var c := conditions()
	_land_timer -= dt
	if _land_timer <= 0.0 and float(c.convection) > 0.0 and float(c.heat) > 0.0:
		_land_timer = LAND_EVERY
		if terrain and terrain.cache:
			var lc := terrain.cache.landclass_at(pos.x, pos.y)
			if lc >= 0:
				_land = CloudConvection.land_factor(lc)
	c.land = _land
	var r := evaluate(c, pos, agl, _t)
	Props.set_v("environment/ac_cloud_density", r.density)
	Props.set_v("environment/ac_in_cloud", r.in_cloud)
	Props.set_v("environment/cloud_base_m", r.base_m)
	Props.set_v("environment/cloud_top_m", r.top_m)
	Props.set_v("environment/cloud_kind", r.kind)
	Props.set_v("environment/turbulence_scale", r.turb_scale)
	Props.set_v("environment/thermal_mps", r.thermal)
	Props.set_v("environment/storm_intensity", r.storm_intensity)
	Props.set_v("environment/storm_core", r.storm_core)
	Props.set_v("environment/storm_shear_mps", r.shear)
	return r
