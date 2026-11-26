extends RefCounted
## Real ILS records next to the simulated ones (tools/14_ils.py -> ils.json; "simulated", "category" are optional
## fields): the nav database, the map label, the precision paint and lights of a runway with an ILS at one end only.
## The data part needs data/processed (skipped without).

const RWY := {"airport": "TEST", "width": 45.0, "length": 3000.0, "ends": [
	{"ident": "09", "x": 0.0, "y": 0.0, "heading_true": 90.0}, {"ident": "27", "x": 3000.0, "y": 0.0, "heading_true": 270.0}]}


func _stn(simulated: Variant, category: Variant) -> Dictionary:
	var s := {"ident": "IABC", "mhz": 110.3}
	if simulated != null:
		s["simulated"] = simulated
	if category != null:
		s["category"] = category
	return s


func test_map_label_shows_category_and_star_only_when_simulated() -> String:
	var real := MapFeatures.ils_label(_stn(false, 2))
	var sim := MapFeatures.ils_label(_stn(true, null))
	var old := MapFeatures.ils_label(_stn(null, null))  # an ils.json from before the field existed: simulated
	if real != "IABC 110.30 CAT II":
		return "real CAT II label is '%s'" % real
	if sim != "IABC 110.30*" or old != sim:
		return "simulated labels '%s' / '%s', want 'IABC 110.30*'" % [sim, old]
	if MapFeatures.ils_label(_stn(false, null)) != "IABC 110.30":
		return "a real ILS of unknown category shows no CAT and no star"
	if MapFeatures.ils_label(_stn(false, 1)) != "IABC 110.30 CAT I" or MapFeatures.ils_label(_stn(false, 3)) != "IABC 110.30 CAT III":
		return "CAT I / CAT III labels wrong"
	return ""


func test_footer_note_only_while_a_simulated_ils_exists() -> String:
	var db := NavDatabase.new()
	db.ils = [{"simulated": false}]
	if MapFeatures.any_simulated(db):
		return "all-real ILS must not show the 'simulated' footer"
	db.ils.append({"simulated": true})
	if not MapFeatures.any_simulated(db):
		return "one simulated ILS must show the footer"
	db.ils = [{}]
	if not MapFeatures.any_simulated(db):
		return "a record without the field counts as simulated"
	return ""


func test_one_ended_ils_gives_precision_paint_and_lights_at_that_end_only() -> String:
	var l := RunwayMarkings.lights_from_ils(RWY, [{"airport": "TEST", "runway": "09"}, {"airport": "OTHER", "runway": "27"}])
	if l.tdz != [true, false] or not l.centreline:
		return "lights %s, want TDZ at 09 only" % [l]
	var u := RunwayMarkings.uniforms(RWY, l)
	var full: int = RunwayMarkings.uniforms(RWY).tdz_bits
	if u.tdz_bits != full or u.tdz_bits_b != 0:
		return "TDZ paint bits %d / %d, want %d at 09 and none at 27" % [u.tdz_bits, u.tdz_bits_b, full]
	if u.tdz_lights != Vector2(1.0, 0.0):
		return "TDZ light fittings %s, want (1, 0)" % [u.tdz_lights]
	var both := RunwayMarkings.uniforms(RWY, RunwayMarkings.lights_from_ils(RWY, [{"airport": "TEST", "runway": "09"}, {"airport": "TEST", "runway": "27"}]))
	if both.tdz_bits != full or both.tdz_bits_b != full:
		return "an ILS at both ends paints both"
	var none := RunwayMarkings.uniforms(RWY, RunwayMarkings.lights_from_ils(RWY, [{"airport": "OTHER", "runway": "09"}]))
	if none.tdz_bits != 0 or none.tdz_bits_b != 0 or none.tdz_lights != Vector2.ZERO:
		return "a runway with no ILS is non-precision: no TDZ bars or fittings"
	if not RunwayMarkings.lights_from_ils(RWY, []).is_empty() or RunwayMarkings.uniforms(RWY).tdz_bits_b != -1:
		return "without ils.json the legacy length-based look stays (tdz_bits_b -1)"
	return ""


func test_approach_lights_follow_the_ils_end() -> String:
	var r := AirportLights.describe(RWY, ["09"])
	if r.ils != [true, false]:
		return "describe ils flags %s" % [r.ils]
	var hf := func(_x: float, _y: float) -> float: return 0.0
	var precision := LightSet.new(Vector2.ZERO)
	var flash := LightSet.new(Vector2.ZERO)
	var simple := LightSet.new(Vector2.ZERO)
	var no_flash := LightSet.new(Vector2.ZERO)
	ApproachLights.build(r, 0, hf, precision, flash)
	ApproachLights.build(r, 1, hf, simple, no_flash)
	if flash.count == 0 or no_flash.count != 0:
		return "the ILS end has the flashing precision system (%d flashers), the other end none (%d)" % [flash.count, no_flash.count]
	if precision.count <= simple.count or simple.count == 0:
		return "precision %d lights vs simple %d for a 3000 m non-ILS end" % [precision.count, simple.count]
	return ""


func test_atc_says_ils_only_for_an_ils_runway() -> String:
	var w := {"ils": ["09"]}
	if AtcProfile.approach_kind(w, "09") != "ILS" or AtcProfile.approach_kind(w, "27") != "visual":
		return "ILS approach on 09, visual on the end without one"
	return ""


func test_nav_database_reads_the_new_fields() -> String:
	var db := NavDatabase.new()
	if db.ils.is_empty():
		return ""  # no data/processed: skipped
	for s in db.ils:
		if not s.has("simulated") or not s.has("category") or typeof(s.simulated) != TYPE_BOOL:
			return "ILS %s misses simulated / category" % s.ident
	return ""


func test_ils_json_real_records_are_consistent() -> String:
	var il = Paths.load_json("ils.json")
	var rw = Paths.load_json("runways.json")
	if not il is Array or rw == null:
		return ""
	var ends := {}
	for r in rw.runways:
		for e in r.ends:
			ends[str(r.airport) + "/" + str(e.ident)] = true
	var real := []
	for s in il:
		if not ends.has(str(s.airport) + "/" + str(s.runway)):
			return "ILS %s is on a runway end that is not in runways.json" % s.ident
		if not s.has("simulated"):
			return "ILS %s has no 'simulated' flag" % s.ident
		if not s.simulated:
			real.append(s)
			var cat := int(s.get("category", 0))
			if cat < 0 or cat > 3:
				return "ILS %s category %d" % [s.ident, cat]
	for s in il:
		if s.simulated:
			for q in real:
				var d := Vector2(s.threshold.x, s.threshold.y).distance_to(Vector2(q.threshold.x, q.threshold.y))
				if d < 150.0 * 1852.0 and absf(float(s.freq_mhz) - float(q.freq_mhz)) < 0.001:
					return "simulated %s shares %.2f MHz with real %s %.0f nm away" % [s.ident, s.freq_mhz, q.ident, d / 1852.0]
	return ""
