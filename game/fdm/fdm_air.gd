class_name FdmAir
extends RefCounted
## The air mass between the property tree and the FDM, read by FdmNode each tick: environment/wind_ned (Weather),
## environment/gust_pqr (rotary gusts, body rad/s; Weather writes it every tick, this takes it), QNH, the ISA offset and humidity. Also publishes the aircraft's
## wing span (fdm/wingspan_m), which the rotary gusts scale with.


static func read(fdm: FDM) -> void:
	Props.set_v("fdm/wingspan_m", float(fdm.cfg.metrics.get("wingspan_m", 11.0)))
	if Props.has("environment/wind_ned"):
		fdm.wind_ned = Props.get_v("environment/wind_ned")
	fdm.gust_pqr = Props.get_v("environment/gust_pqr", Vector3.ZERO)
	Props.set_v("environment/gust_pqr", Vector3.ZERO)  # taken: a stale value never keeps rolling the aircraft
	if Props.has("environment/qnh_pa"):
		fdm.atmo.qnh_pa = Props.get_f("environment/qnh_pa")
		fdm.atmo.delta_t = Props.get_f("environment/delta_t")
		fdm.atmo.humidity_k = 0.0
		if Props.get_b("weather/use_humidity", false):
			var h := maxf(Props.get_f("fdm/alt_m", 0.0), 0.0)
			var t_c := Props.get_f("weather/temp_c", 15.0) - AtmosphereISA.L * h
			var p_hpa := Props.get_f("weather/qnh_hpa", 1013.25) * pow(maxf(1.0 - AtmosphereISA.L * h / AtmosphereISA.T0, 0.2), AtmosphereISA.EXP)
			fdm.atmo.humidity_k = AtmosphereISA.virtual_extra_k(t_c, Props.get_f("weather/dewpoint_c"), p_hpa)
