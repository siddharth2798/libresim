// Terminal look for building.gdshader (included after hash / vnoise / box1 and building_night.gdshaderinc).
// Generic passenger terminals (researched in tools/ref/terminals_reference.json, no landmark model) are roof
// type 2: on the walls CUSTOM0.rgb = cladding colour (sRGB), band = glazing share x 200, pid = glass luminance
// x 63 (tools/building_geom.py). The facade is a curtain wall: a low plinth, one tall glazed band with
// mullions (1.5 m) and transoms (each 4.5 m storey), a solid fascia under the roof edge and structural piers
// every bay; the less glass, the deeper the fascia, the wider the piers and the more spandrel per storey.
// No storey windows, balconies, shopfronts or tanks. At night the glazed hall glows evenly (not random rooms).

const float TERM_STOREY = 4.5;  // m, terminal_ref.STOREY_M
const float TERM_BAY = 18.0;  // m between structural piers
const float TERM_MULL = 1.5;  // m between mullions

vec3 term_lin(vec3 c) { return pow(c, vec3(2.2)); }  // stored sRGB -> linear albedo

// Flat terminal roof: the reference roof colour, standing-seam lines fading with distance, mottling.
vec3 terminal_roof(vec3 rgb, vec3 w, float band) {
	vec3 col = term_lin(rgb) * 0.92;
	float seam = w.x / 0.6;
	float fs = fwidth(seam);
	col *= mix(0.97, 0.93 + 0.07 * smoothstep(0.0, 0.12, fract(seam)), 1.0 - smoothstep(0.2, 0.6, fs));
	col *= 0.93 + 0.1 * vnoise(w.xz * 0.05) + 0.04 * vnoise(w.xz * 0.7);
	if (band <= 200.0) {  // parapet strip: light cap on the outer edge
		float e = band / 200.0;
		col = mix(col, col * 1.08 + 0.02, (1.0 - smoothstep(0.30, 0.38, e)) * (1.0 - smoothstep(0.1, 0.3, fwidth(e))));
	}
	return col;
}

// Wall of a terminal. u: metres along the facade, hg: height above the ground, Hh: wall height, share: glazing
// share 0..1, glum: glass luminance 0..1. Writes col / emit / gloss; returns the facade's far average colour.
vec3 terminal_wall(vec3 rgb, float share, float glum, float u, float hg, float Hh, float id, float nl, vec3 fogc,
		out vec3 col, out vec3 emit, out float gloss) {
	vec3 clad = term_lin(rgb) * (0.92 + 0.08 * vnoise(vec2(u * 0.05, hg * 0.1) + id * 9.0));
	float plinth = 0.7;
	float fascia = max(1.0, (1.0 - share) * Hh * 0.45);
	float top = max(Hh - fascia, plinth + 2.0);
	float pier_w = 0.5 + (1.0 - share) * 2.5;
	float spandrel = clamp((0.75 - share) * 0.9, 0.0, 0.45);  // share of each storey that is solid
	float fu = fwidth(u);
	float fh = fwidth(hg);
	float detail = 1.0 - smoothstep(0.15, 0.5, max(fu, fh) / TERM_MULL);
	float bay = u / TERM_BAY;
	float pier = 1.0 - box1(fract(bay) * TERM_BAY, pier_w * 0.5, TERM_BAY - pier_w * 0.5, fu);
	float sto = hg / TERM_STOREY;
	float spd = 1.0 - box1(fract(sto), spandrel, 1.0, fwidth(sto));
	float band_m = box1(hg, plinth, top, fh);  // the glazed band
	float glazed = band_m * (1.0 - pier) * (1.0 - spd);
	float glazed_avg = clamp((top - plinth) / max(Hh, 1.0), 0.0, 1.0) * (1.0 - pier_w / TERM_BAY) * (1.0 - spandrel);
	float gm = mix(glazed_avg, glazed, detail);
	// mullions and transoms: thin light frames across the glass
	float mull = 1.0 - box1(fract(u / TERM_MULL), 0.035, 0.965, fu / TERM_MULL);
	float tran = 1.0 - box1(fract(sto), 0.03, 0.97, fwidth(sto));
	float frame = max(mull, tran) * glazed * detail;
	// glass: the researched tone, darker inside, reflecting more sky toward the top of the hall
	vec3 gl = vec3(0.82, 0.96, 1.06) * pow(glum, 2.2) * 0.45;
	gl = mix(gl, fogc * 0.45, 0.2 + 0.3 * smoothstep(plinth, top, hg));
	gl *= 0.9 + 0.2 * hash(vec2(floor(u / TERM_MULL), floor(sto)) + id);
	vec3 fr = mix(clad, vec3(0.55, 0.57, 0.58), 0.5);
	col = mix(clad, gl, gm);
	col = mix(col, fr, frame * 0.8);
	col *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.6, Hh - hg)) * detail;  // shadow line under the roof edge
	gloss = gm * (1.0 - frame) * 0.85;
	emit = vec3(0.0);
	if (nl > 0.0) {
		// evenly lit hall: warm white, slightly brighter on the lower storeys, a little variation per bay
		vec3 lamp = vec3(1.0, 0.9, 0.76);
		float vb = 0.85 + 0.3 * hash(vec2(floor(bay), id * 3.0));
		float lower = mix(1.15, 0.85, smoothstep(plinth, top, hg));
		emit = lamp * WIN_EMIT * 0.75 * gm * (1.0 - frame) * vb * lower * smoothstep(0.0, 0.6, nl);
	}
	return mix(clad, gl, glazed_avg);
}
