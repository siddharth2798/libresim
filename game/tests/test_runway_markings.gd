extends RefCounted
## Realistic runways, Stage 1 (world/runway_markings.gd, world/runway_glyphs.gd): the ICAO Annex 14 marking layout
## that world/runway_v2.gdshader paints, and the designator glyph atlas.

const VABB := {"airport": "VABB", "width": 60.0, "length": 3470.2, "ends": [
	{"ident": "27", "x": -54652.8, "y": 37589.9, "heading_true": 269.37},
	{"ident": "09", "x": -58122.8, "y": 37551.7, "heading_true": 89.37}]}


func test_threshold_stripes_follow_the_runway_width() -> String:
	for c in [[18.0, 4], [23.0, 6], [30.0, 8], [45.0, 12], [60.0, 16], [50.0, 12], [35.0, 8], [15.0, 4], [75.0, 16]]:
		var n := RunwayMarkings.stripe_count(c[0])
		if n != c[1]:
			return "%d m wide: %d stripes, want %d" % [c[0], n, c[1]]
	for w in [18.0, 30.0, 45.0, 60.0]:
		var reach := RunwayMarkings.stripe_pitch(w) * RunwayMarkings.stripe_count(w) / 2.0
		if absf(reach - minf(w * 0.5 - 3.0, 27.0)) > 0.01:
			return "%d m wide: stripes reach %.2f m from the axis, want 3 m from the edge (max 27 m)" % [w, reach]
	return ""


func test_aiming_point_and_touchdown_zone_follow_the_length() -> String:
	for c in [[3000.0, 400.0], [2400.0, 400.0], [2000.0, 300.0], [1200.0, 300.0], [1000.0, 250.0], [700.0, 150.0]]:
		var a := RunwayMarkings.aiming_point(c[0])
		if a.dist != c[1]:
			return "%d m: aiming point at %d m, want %d" % [c[0], a.dist, c[1]]
	var big := RunwayMarkings.aiming_point(3470.0, 60.0)
	if big.length < 45.0 or big.length > 60.0 or big.width < 6.0 or big.width > 10.0 or big.inner * 2.0 < 18.0 or big.inner * 2.0 > 22.5:
		return "long-runway aiming point outside 45-60 x 6-10 m, 18-22.5 m apart: %s" % big
	for c in [[3000.0, 6], [2000.0, 4], [1300.0, 3], [1000.0, 2], [700.0, 1]]:
		if RunwayMarkings.tdz_pair_count(c[0]) != c[1]:
			return "%d m: %d TDZ pairs, want %d" % [c[0], RunwayMarkings.tdz_pair_count(c[0]), c[1]]
	var pos := RunwayMarkings.tdz_positions(3470.0)
	if pos != [150.0, 300.0, 600.0, 750.0, 900.0]:
		return "TDZ pairs on a 3470 m runway at %s, want every 150 m to 900 m without the one beside the 400 m aiming point" % [pos]
	if RunwayMarkings.tdz_positions(2000.0) != [150.0, 450.0, 600.0]:
		return "TDZ pairs on a 2000 m runway at %s (the 300 m pair coincides with the aiming point)" % [RunwayMarkings.tdz_positions(2000.0)]
	if [RunwayMarkings.tdz_bars(150.0), RunwayMarkings.tdz_bars(300.0), RunwayMarkings.tdz_bars(600.0), RunwayMarkings.tdz_bars(900.0)] != [3, 3, 2, 1]:
		return "TDZ bars should go triple, double, single"
	return ""


func test_line_widths() -> String:
	if RunwayMarkings.centreline_width(45.0) != 0.9 or RunwayMarkings.centreline_width(30.0) != 0.45:
		return "centreline 0.9 m on runways 45 m or wider, else 0.45 m"
	if RunwayMarkings.edge_width(30.0) != 0.9 or RunwayMarkings.edge_width(23.0) != 0.45:
		return "edge stripes 0.9 m on runways 30 m or wider, else 0.45 m"
	return ""


func test_designator_glyph_indices() -> String:
	for c in [["09", [0, 9, -1]], ["27", [2, 7, -1]], ["14L", [1, 4, 10]], ["32R", [3, 2, 12]], ["9", [0, 9, -1]], ["18C", [1, 8, 11]]]:
		if RunwayMarkings.designator(c[0]) != c[1]:
			return "%s -> %s, want %s" % [c[0], RunwayMarkings.designator(c[0]), c[1]]
	if RunwayMarkings.designator_end("14L") - RunwayMarkings.designator_end("14") != 15.0:
		return "the letter (9 m + 6 m gap) should push the number 15 m further in"
	return ""


func test_seed_is_stable_and_per_runway() -> String:
	var a := RunwayMarkings.runway_seed("VABB", "27")
	if a != RunwayMarkings.runway_seed("VABB", "27") or a == RunwayMarkings.runway_seed("VABB", "32") or a == RunwayMarkings.runway_seed("VAJJ", "27"):
		return "seed must repeat for one runway and differ between runways"
	if a < 0.0 or a >= 1000.0:
		return "seed out of range: %f" % a
	return ""


func test_uniforms_for_vabb_27() -> String:
	var u := RunwayMarkings.uniforms(VABB)
	if u.thr_k != 8 or u.des_a != Vector4(2, 7, -1, 0) or u.des_b != Vector4(0, 9, -1, 0):
		return "VABB 27/09: %d stripes a side, designators %s / %s" % [u.thr_k, u.des_a, u.des_b]
	if u.aim.x != 400.0 or u.tdz_bits != 0b111011:
		return "aiming point %.0f m, TDZ bits %s" % [u.aim.x, String.num_int64(u.tdz_bits, 2)]
	var first: float = u.cl_start
	var last: float = first + u.cl_count * 50.0 - 20.0
	if first < RunwayMarkings.designator_end("27") + 12.0 - 0.01 or absf(first - (u.length_m - last)) > 0.01:
		return "centreline dashes %.1f..%.1f m should start 12 m past the designator and sit symmetrically" % [first, last]
	if u.rubber.x <= u.rubber.y:
		return "27 lands into the prevailing westerlies: it should carry more rubber than 09"
	return ""


func test_glyph_atlas_draws_every_glyph_inside_its_cell() -> String:
	var img := RunwayGlyphs.atlas()
	var cw := int(RunwayGlyphs.CELL.x * RunwayGlyphs.PPM)
	if img.get_width() != cw * RunwayGlyphs.COUNT or not img.has_mipmaps():
		return "atlas %dx%d (mipmaps %s)" % [img.get_width(), img.get_height(), img.has_mipmaps()]
	for g in RunwayGlyphs.COUNT:
		var ink := 0.0
		var edge := 0.0
		for y in range(0, img.get_height(), 4):
			for x in range(0, cw, 2):
				var v := img.get_pixel(g * cw + x, y).r
				ink += v
				if x < 6 or x > cw - 8 or y < 6 or y > img.get_height() - 8:
					edge += v
		if ink < 150.0:
			return "glyph %d is almost empty" % g
		if edge > 0.5:
			return "glyph %d spills into its margin" % g
	# the 0 is closed at the top, the 7 is not on its bottom-left
	var at := func(g: int, gx: float, gy: float) -> float:
		return img.get_pixel(g * cw + int((gx + RunwayGlyphs.MARGIN) * RunwayGlyphs.PPM), int((RunwayGlyphs.CELL.y - RunwayGlyphs.MARGIN - gy) * RunwayGlyphs.PPM)).r
	if at.call(0, 1.5, 8.6) < 0.5 or at.call(0, 1.5, 4.5) > 0.5 or at.call(7, 0.3, 0.3) > 0.5 or at.call(10, 0.35, 4.5) < 0.5:
		return "glyph shapes are off (0 top / hole, 7 foot, L stem)"
	return ""
