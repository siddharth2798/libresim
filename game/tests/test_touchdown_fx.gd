extends RefCounted
## Touchdown smoke / skid-mark trigger logic (world/touchdown_fx.gd).


func test_fx_puff_triggers_only_on_landing() -> String:
	if TouchdownFx.puff(28.0, 0.8, 5.0) <= 0.2:
		return "normal landing (55 kt, 160 fpm) should puff"
	if TouchdownFx.puff(28.0, 0.8, 0.2) != 0.0:
		return "a wheel that barely left the ground must not puff (bounce / taxi)"
	if TouchdownFx.puff(6.0, 0.8, 5.0) != 0.0:
		return "taxi speed must not puff"
	return ""


func test_fx_puff_scales_with_speed_and_sink() -> String:
	var soft := TouchdownFx.puff(26.0, 0.3, 4.0)
	var hard := TouchdownFx.puff(32.0, 2.4, 4.0)
	if not (hard > soft and hard <= 1.0 and soft > 0.0):
		return "puff should grow with speed and sink (soft %.2f, hard %.2f)" % [soft, hard]
	if TouchdownFx.mark_length(hard) <= TouchdownFx.mark_length(soft):
		return "skid mark should be longer on a harder landing"
	return ""
