extends RefCounted
## FanBlur.disc_alpha only. Does not load a glb.


func test_disc_alpha() -> String:
	if not is_equal_approx(FanBlur.disc_alpha(0.0), 0.0):
		return "n1 0 -> %s" % FanBlur.disc_alpha(0.0)
	if not is_equal_approx(FanBlur.disc_alpha(25.0), 0.0):
		return "n1 25 -> %s" % FanBlur.disc_alpha(25.0)
	var mid := FanBlur.disc_alpha(40.0)
	if mid <= 0.0 or mid >= 0.8:
		return "n1 40 -> %s" % mid
	if not is_equal_approx(FanBlur.disc_alpha(58.0), 0.8):
		return "n1 58 -> %s" % FanBlur.disc_alpha(58.0)
	if not is_equal_approx(FanBlur.disc_alpha(100.0), 0.8):
		return "n1 100 -> %s" % FanBlur.disc_alpha(100.0)
	return ""
