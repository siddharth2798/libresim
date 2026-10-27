extends RefCounted
## Eye-like auto exposure (world/auto_exposure.gd): the target for bright / dark scenes, the
## asymmetric smoothing, and the preset switch (off on Low).


func test_target_follows_scene_brightness() -> String:
	var noon := AutoExposure.scene_luminance(1.3, 0.87, 0.0, 0.7, 0.38, 0.0)
	var t_noon := AutoExposure.target_for(noon)
	if absf(t_noon - 1.0) > 0.12:
		return "a clear noon should stay near exposure 1, got %.2f (luminance %.2f)" % [t_noon, noon]
	var shade := AutoExposure.scene_luminance(1.3, 0.87, 1.0, 0.7, 0.38, -0.5)  # under a cloud, looking down
	var overcast := AutoExposure.scene_luminance(0.05, 0.87, 0.0, 1.0, 0.15, 0.0)
	var night := AutoExposure.scene_luminance(0.0, -0.5, 0.0, 0.5, 0.003, 0.0)
	var t_shade := AutoExposure.target_for(shade)
	var t_over := AutoExposure.target_for(overcast)
	var t_night := AutoExposure.target_for(night, 1.0)
	if not (t_noon < t_shade and t_shade < t_over + 0.3 and t_over < t_night + 0.3 and t_shade > 1.05):
		return "darker scenes should raise exposure: noon %.2f shade %.2f overcast %.2f night %.2f" % [t_noon, t_shade, t_over, t_night]
	var bright := AutoExposure.target_for(1.5)
	if bright >= 1.0 or bright < AutoExposure.MIN:
		return "a very bright scene should lower exposure within the minimum: %.2f" % bright
	if t_night > AutoExposure.MAX_NIGHT + 1e-6 or AutoExposure.target_for(0.001) > AutoExposure.MAX + 1e-6:
		return "exposure must respect the caps (night %.2f)" % t_night
	return ""


func test_view_direction_and_shade_change_the_estimate() -> String:
	var down := AutoExposure.scene_luminance(1.3, 0.8, 0.0, 0.7, 0.5, -0.8)
	var up := AutoExposure.scene_luminance(1.3, 0.8, 0.0, 0.7, 0.5, 0.8)
	var sunlit := AutoExposure.scene_luminance(1.3, 0.8, 0.0, 0.7, 0.5, 0.0)
	var shaded := AutoExposure.scene_luminance(1.3, 0.8, 1.0, 0.7, 0.5, 0.0)
	if down == up:
		return "looking at the sky vs the ground should change the estimate"
	return "" if shaded < sunlit else "cloud shade should lower the luminance estimate"


func test_smoothing_is_gradual_and_asymmetric() -> String:
	var ae := AutoExposure.new()
	if ae.step(0.016, 1.3) != 1.3:
		return "the first update should jump to the target (no fade-in at load)"
	ae = AutoExposure.new()
	ae.step(0.016, 1.0)
	for i in 60:  # 1 s into a dark scene (target 1.4)
		ae.step(1.0 / 60.0, 1.4)
	var after_1s := ae.value
	if not (after_1s > 1.0 and after_1s < 1.2):
		return "1 s into a dark scene exposure should have moved only part of the way: %.3f" % after_1s
	for i in 60 * 8:
		ae.step(1.0 / 60.0, 1.4)
	if absf(ae.value - 1.4) > 0.02 or ae.value > 1.4 + 1e-6:
		return "exposure should settle on the target without overshoot: %.3f" % ae.value
	var bright := AutoExposure.new()
	bright.step(0.016, 1.4)
	for i in 60:
		bright.step(1.0 / 60.0, 1.0)
	var dark := AutoExposure.new()
	dark.step(0.016, 1.0)
	for i in 60:
		dark.step(1.0 / 60.0, 1.4)
	if absf(1.4 - bright.value) / 0.4 <= absf(dark.value - 1.0) / 0.4:
		return "adapting to bright (%.3f) should be faster than adapting to dark (%.3f)" % [bright.value, dark.value]
	return ""


func test_preset_switch() -> String:
	for p in Graphics.ORDER:
		if not Graphics.PRESETS[p].has("ae"):
			return "%s has no 'ae' flag" % p
		if bool(Graphics.PRESETS[p].ae) != (p != "low"):
			return "auto exposure should be on everywhere except Low (%s)" % p
	return ""


func test_exposure_stacks_with_night_and_glare() -> String:
	# SkyTime multiplies: NightSky base (1 .. 1.45) x auto exposure (0.8 .. 1.5) x glare pull (0.8 ..1)
	var worst := lerpf(1.0, 1.45, 1.0) * AutoExposure.MAX_NIGHT
	if worst > 1.8:
		return "night base x auto exposure peaks at %.2f, too bright" % worst
	if 0.8 * AutoExposure.MIN * 1.0 < 0.6:
		return "bright scene x glare pull falls below 0.6"
	return ""
