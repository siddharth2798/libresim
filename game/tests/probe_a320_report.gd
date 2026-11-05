extends RefCounted
## Output of probe_a320_landing.gd: start check, idle-descent result, the LANDING RESULT line and a table of the key numbers.


## Prints everything and returns the exit code (0 = PASS).
static func print_all(p: Node, s: Dictionary) -> int:
	var m = p.meter
	var a = m.start
	var b = m.start_end
	if not a.is_empty() and not b.is_empty():
		print("START CHECK t=0: %.0f ft above the field (%.2f nm out), ias %.1f kt, vs %.0f fpm, pitch %.2f, alpha %.2f, gear down flaps %.1f deg, lever %.3f n1 %.1f%% thrust %.1f kN/engine, mass %.0f kg" % [
			a.hw, -a.along / 1852.0, a.ias, a.vs, a.pitch, a.alpha, a.flap_deg, a.lever, a.n1, a.thrust_kn, a.mass])
		print("START CHECK hands off 8 s: d_alt %+.0f ft, d_ias %+.1f kt, vs %.0f fpm, pitch %.2f, lever %.3f" % [b.hw - a.hw, b.ias - a.ias, b.vs, b.pitch, b.lever])
	if p.pilot.idle_mode:
		return _idle(p)
	var r: Dictionary = m.stats(p.st.length, p.st.width)
	var why: String = m.verdict(p.st.length, p.st.width, s.crashed, Props.get_v("damage/events", []), Props.get_b("damage/structure"))
	var ok := why == ""
	var ab: String = ["off", "LO", "MED", "MAX"][p.pilot.autobrake]
	print("LANDING RESULT %s reason=%s autobrake=%s reverse=%d wind=%03d/%d td_ias=%.1f td_gs=%.1f sink_fpm=%.0f pitch=%.1f bank=%.1f g=%.2f along_m=%.0f roll_m=%.0f roll60_m=%.0f ld50_m=%.0f decel_mean=%.2f decel_peak=%.2f bounces=%d t=%.0f" % [
		"PASS" if ok else "FAIL", why if why != "" else "landed_and_stopped_on_runway", ab, p.pilot.reverse,
		int(Session.setup.wind_dir_deg), int(Session.setup.wind_kt), r.td_ias, r.td_gs, r.td_sink_fpm, r.td_pitch, r.td_bank, r.td_g,
		r.td_along, r.get("roll_m", -1.0), r.get("roll60_m", -1.0), r.get("ld_m", -1.0), r.get("mean_decel", 0.0), r.peak_decel,
		r.bounces, p.t])
	print("LANDING damage: crashed=%s events=%s structure=%s" % [s.crashed, Props.get_v("damage/events", []), Props.get_b("damage/structure")])
	_table(r, p)
	return 0 if ok else 1


static func _table(r: Dictionary, p: Node) -> void:
	print("LANDING TABLE (runway %s %s, %.0f m, mass at touchdown %.0f kg, vapp %.1f kt)" % [p.st.apt, p.st.ident, r.rwy_len, r.td_mass, p.pilot.vapp])
	print("  gate        IAS   GS    V/S    FPA   pitch  alpha  N1   thrust kN/eng")
	for k in ["1000", "500", "50"]:
		print("  %4s ft  %5.1f %5.1f %6.0f %6.2f %6.2f %6.2f %5.1f %6.1f" % [k, r["ias_" + k], r["gs_" + k], r["vs_" + k], r["fpa_" + k],
			r["pitch_" + k], r["alpha_" + k], r["n1_" + k], r["thrust_" + k]])
	print("  at 1000 ft: Vls %.1f kt, alpha %.1f (protection %.1f, max %.1f deg), IAS - Vls %.1f kt" % [r.vls_1000, r.alpha_1000, r.aprot_1000, r.amax_1000, r.ias_1000 - r.vls_1000])
	print("  final 900-150 ft: n1 %.1f %%, lever %.3f, thrust %.1f kN/engine, mean fpa %.2f deg" % [r.n1_final, r.lever_final, r.thrust_final_kn, r.fpa_final])
	print("  flare: from %.0f ft (pitch %.1f) for %.1f s, touchdown pitch %.1f (change %+.1f), alpha %.1f, n1 at touchdown %.1f" % [
		r.flare_ra, r.flare_pitch0, r.flare_t_s, r.td_pitch, r.td_pitch - r.flare_pitch0, r.td_alpha, r.td_n1])
	print("  touchdown: ias %.1f gs %.1f kt, sink %.0f fpm (wheel) / %.0f fpm (fdm), g %.2f (peak %.2f), pitch %.1f, bank %.1f, along %.0f m, cross %.1f m" % [
		r.td_ias, r.td_gs, r.td_sink_fpm, absf(r.td_vs_fpm), r.td_g, r.peak_nz, r.td_pitch, r.td_bank, r.td_along, r.td_cross])
	print("  rollout: nose wheel +%.1f s, spoilers >10 deg +%.1f s (full +%.1f s), reverse deployed +%.1f s, autobrake on +%.1f s, bounces %d (max %.1f ft)" % [
		r.nose_s, r.spoil_s, r.spoil_full_s, r.rev_s, r.autobrake_s, r.bounces, r.bounce_ft])
	print("  decel: mean %.2f m/s2 (touchdown to stop), %.2f (80 to 20 kt), peak 1 s %.2f; roll %.0f m (to 60 kt %.0f m, %.0f s), from 50 ft %.0f m, max centreline offset %.1f m" % [
		r.get("mean_decel", 0.0), r.get("decel_80_20", 0.0), r.peak_decel, r.get("roll_m", -1.0), r.get("roll60_m", -1.0), r.get("roll_s", 0.0), r.get("ld_m", -1.0), r.max_cross])


static func _idle(p: Node) -> int:
	var g: Array = p._idle_g.slice(-1000)  # the last 8 s
	if g.is_empty():
		print("IDLE DESCENT FAIL no steady samples")
		return 1
	var sum := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for x in g:
		for i in 8:
			sum[i] += float(x[i])
	var n := float(g.size())
	print("IDLE DESCENT PASS samples=%d fpa=%.2f deg vs=%.0f fpm n1=%.1f thrust=%.1f kN/engine ias=%.1f pitch=%.2f alpha=%.2f lever=%.3f vapp=%.1f" % [
		g.size(), sum[0] / n, sum[4] / n, sum[1] / n, sum[2] / n, sum[3] / n, sum[5] / n, sum[6] / n, sum[7] / n, p.pilot.vapp])
	return 0
