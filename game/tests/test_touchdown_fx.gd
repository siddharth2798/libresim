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


func test_fx_marks_follow_landing_smoothness() -> String:
	var butter := TouchdownFx.mark_strength(0.35, 28.0)   # ~70 fpm
	var smooth := TouchdownFx.mark_strength(1.0, 28.0)    # ~200 fpm
	var firm := TouchdownFx.mark_strength(2.2, 28.0)      # ~430 fpm
	var hard := TouchdownFx.mark_strength(4.5, 28.0)      # ~890 fpm
	if butter > 0.03:
		return "a butter landing should leave no mark (%.3f)" % butter
	if not (smooth < firm and firm < hard and smooth > 0.03):
		return "mark strength should rise with sink rate: %.2f %.2f %.2f" % [smooth, firm, hard]
	if TouchdownFx.mark_length(hard) < 2.0 * TouchdownFx.mark_length(smooth):
		return "a hard landing's mark should be much longer than a smooth one's"
	if TouchdownFx.mark_alpha(smooth) > 0.45 or TouchdownFx.mark_alpha(hard) < 0.8:
		return "smooth marks should be faint, hard ones dark (%.2f / %.2f)" % [TouchdownFx.mark_alpha(smooth), TouchdownFx.mark_alpha(hard)]
	return ""
