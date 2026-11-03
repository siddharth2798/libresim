// Shore look for terrain.gdshader's water branch. sd_tex (tools/21_shore.py, same source tile and uv as the
// land-class mask): R = 128 + signed distance to the shore in metres (positive over water), G = openness
// (how far open water reaches: open sea 1, lakes and narrow backwaters low).

uniform sampler2D sd_tex : filter_linear, repeat_disable;
// 1 when screen-space reflections are on (Forward+ high presets): the fake sky blend in the albedo is
// lowered, SSR gives the real reflection; the rest stays as the fallback for rays that leave the screen.
global uniform float water_ssr;

// --- tuning (all by eye) ---
const float WATER_SKY_MAX = 0.85;        // cap of the fresnel sky blend (no SSR)
const float WATER_SSR_SKY_KEEP = 0.35;   // share of that blend kept when water_ssr = 1
// fine wave layer: ripples (wavelength ~0.4..3 m) across the main wave field, other direction and scale
const float FINE_SLOPE = 0.09;           // slope of the first fine octave (next ones x0.7)
const float FINE_F0 = 0.33;              // cycles per metre of the first fine octave
const float FINE_DIR = 0.7;              // rad, rotation from the main wave field
const vec2 FINE_FADE = vec2(60.0, 520.0);   // camera distance (m): full .. gone
// open water: deeper / bluer beyond the shoals (sd_m saturates at +127 m)
const vec3 DEEP_NEAR = vec3(0.05, 0.13, 0.15);   // Arabian Sea: grey-green-blue (the old single colour)
const vec3 DEEP_FAR = vec3(0.032, 0.088, 0.135); // open sea offshore: darker, bluer
const float DEEP_FAR_AMOUNT = 0.75;
// sun glint: a broad statistical lobe for the wave slopes the normals no longer carry (far), plus a
// soft glitter of sparkles at mid range; Godot's own GGX highlight (roughness 0.06) does the near water
const float GLINT_STRENGTH = 0.55;       // albedo added at the lobe peak
const float GLINT_MAX = 0.9;
const float GLINT_SIG_NEAR = 0.05;       // slope spread (tan) still unresolved close up
const float GLINT_SIG_FAR = 0.13;        // slope spread once the wave normals have faded (open sea, full chop)
const float GLINT_NEAR_WEIGHT = 0.25;    // the near lobe overlaps Godot's specular: keep it small
const float SPARKLE_CELL = 2.6;          // m, glitter cell
const float SPARKLE_MIX = 0.8;

// integer-lattice hash (no sin: stays exact at large coordinates)
float w_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
// value noise with its analytic gradient (x value, yz d/dp), lattice wrapped every 1024 cells so the
// coordinates stay small; the wrap is seamless because both corners are wrapped
vec3 w_noise_d(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f), du = 6.0 * f * (1.0 - f);
	vec2 i0 = mod(i, 1024.0), i1 = mod(i + 1.0, 1024.0);
	float a = w_hash(i0), b = w_hash(vec2(i1.x, i0.y)), c = w_hash(vec2(i0.x, i1.y)), d = w_hash(i1);
	float k = a - b - c + d;
	return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y, du * vec2(b - a + k * u.y, c - a + k * u.x));
}

// Fine ripple slope (east, north) on top of wave_grad. Each octave is dropped before it reaches the pixel
// size (px = metres per pixel), so it never shimmers; the whole layer fades out by FINE_FADE.y.
vec2 water_fine_grad(vec2 en, float t, float dist, float px) {
	float k = 1.0 - smoothstep(FINE_FADE.x, FINE_FADE.y, dist);
	if (k <= 0.0) { return vec2(0.0); }
	vec2 g = vec2(0.0);
	float a = FINE_SLOPE, f = FINE_F0, ang = FINE_DIR;
	for (int i = 0; i < 3; i++) {
		float ok = 1.0 - smoothstep(0.12, 0.3, px * f);
		if (ok <= 0.0) { break; }
		vec2 dir = vec2(cos(ang), sin(ang));
		mat2 r = mat2(dir, vec2(-dir.y, dir.x));       // columns: along, across the ripple travel
		vec2 q = (en * r) * vec2(f, f * 1.6);          // ripples longer across than along their travel
		q.x -= t * sqrt(9.81 / (6.2832 * f)) * f;      // deep-water phase speed of that wavelength
		vec2 gq = w_noise_d(q + float(i) * 37.1).yz * vec2(1.0, 1.6);
		g += r * gq * (a * ok);                        // back to (east, north)
		a *= 0.7; f *= 2.3; ang += 1.9;
	}
	return g * k;
}

// Deep-water colour: offshore (saturated shore distance, open water) is darker and bluer; creeks and
// rivers (sea = 0) and sheltered water keep the old colour. Returns (colour, sat-tint weight).
vec4 water_deep(float sd_m, float open, float sea, vec2 en) {
	float off = smoothstep(60.0, 125.0, sd_m) * smoothstep(0.5, 0.9, open) * sea;
	off *= 0.8 + 0.4 * w_noise_d(en * 0.0007).x;  // slow km-scale patches so the open sea is not one flat tone
	off = clamp(off * DEEP_FAR_AMOUNT, 0.0, 1.0);
	return vec4(mix(DEEP_NEAR, DEEP_FAR, off), mix(0.4, 0.28, off));
}

// Fresnel sky blend for the albedo, lowered when SSR provides the reflection.
float water_sky_blend(float fres) {
	return clamp(fres * 0.75 + 0.04, 0.0, WATER_SKY_MAX) * mix(1.0, WATER_SSR_SKY_KEEP, clamp(water_ssr, 0.0, 1.0));
}

// Share of the sun that reaches this water point: sun above the horizon, not overcast, not under the
// shadow of a cloud (same projection as the cloud shadows in terrain.gdshader).
float water_sun_vis(vec2 en, float alt) {
	float vis = smoothstep(0.03, 0.14, cloud_sun.y) * (1.0 - smoothstep(0.55, 0.92, cloud_shadow.y));
	if (vis <= 0.0 || cloud_shadow.z <= 0.0) { return vis; }
	float t = (cloud_shadow.x + 360.0 - alt) / max(cloud_sun.y, 0.08);
	if (t > 0.0 && t < 80000.0) {
		vec2 q = (en + vec2(cloud_sun.x, -cloud_sun.z) * t) / 9000.0 + cloud_uv_off;
		float cov = textureLod(cloud_noise, q, 0.0).r - (1.0 - cloud_shadow.y) * 0.82;
		vis *= 1.0 - smoothstep(0.0, 0.45, cov * 2.6 - 0.2) * clamp(cloud_shadow.z * 1.5, 0.0, 1.0);
	}
	return vis;
}

// Sun glint added to the water albedo. nw = wave normal, vw = towards the camera, both render frame.
// chop 0..1 (sheltered .. open), px = metres per pixel.
vec3 water_glint(vec3 nw, vec3 vw, vec2 en, float alt, float dist, float px, float chop, float t) {
	float vis = water_sun_vis(en, alt);
	if (vis <= 0.0) { return vec3(0.0); }
	vec3 h = normalize(vw + cloud_sun);
	float c = max(dot(h, nw), 1e-3);
	float t2 = (1.0 - c * c) / (c * c);                    // tan^2 of the facet tilt that mirrors the sun
	float lost = smoothstep(150.0, 2500.0, dist);           // wave_grad fade: slope no longer in the normals
	float s2 = GLINT_SIG_NEAR * GLINT_SIG_NEAR + lost * chop * GLINT_SIG_FAR * GLINT_SIG_FAR;
	float lobe = exp(-t2 / s2) * min(1.0, 0.01 / s2);       // wider lobe = dimmer peak (same energy)
	if (lobe < 1e-3) { return vec3(0.0); }
	// glitter: soft dots that twinkle, world-stable, only while a cell is several pixels wide
	float sk = (1.0 - smoothstep(0.12, 0.35, px / SPARKLE_CELL)) * smoothstep(40.0, 140.0, dist);
	float spark = 1.0;
	if (sk > 0.0) {
		vec2 cp = en / SPARKLE_CELL;
		vec2 cell = mod(floor(cp), 4096.0);
		float h1 = w_hash(cell), h2 = w_hash(cell + 71.3);
		float dot_ = 1.0 - smoothstep(0.08, 0.3, length(fract(cp) - 0.25 - 0.5 * vec2(h1, h2)));
		float tw = pow(0.5 + 0.5 * sin(t * (2.5 + 3.0 * h2) + h1 * 6.2832), 6.0);
		spark = mix(1.0, 0.35 + dot_ * tw * 6.0, sk * SPARKLE_MIX);  // dimmer path between bright sparkles
	}
	float fr = 0.5 + 0.5 * pow(1.0 - clamp(dot(vw, h), 0.0, 1.0), 5.0);
	float w = mix(GLINT_NEAR_WEIGHT, 1.0, lost);
	// albedo is lit by N.L: undo most of it so a low sun still lays a path (the light itself dims at dusk)
	float g = lobe * spark * fr * w * vis * GLINT_STRENGTH / max(dot(nw, cloud_sun), 0.25);
	return vec3(min(g, GLINT_MAX));
}

// Foam coverage 0..1 at shore distance d (m, > 0 on the water side): a swash line at the waterline and
// soft wave fronts running shoreward on open water. Fades out with distance so it never shimmers.
float shore_foam(float d, float open, vec2 en, float dist, float t) {
	float k = 1.0 - smoothstep(2500.0, 6000.0, dist);
	if (k <= 0.0 || d > 120.0) { return 0.0; }
	float n = vnoise(en * 0.09 + vec2(t * 0.03, 0.0)) * 0.6 + vnoise(en * 0.45 - vec2(0.0, t * 0.08)) * 0.4;
	float dw = d + (n - 0.5) * 7.0;
	float surf = smoothstep(0.2, 0.55, open);  // calm backwaters get only a thin swash line
	k *= smoothstep(0.22, 0.4, open);           // rivers, creeks and ponds: no foam at all
	float swash = (1.0 - smoothstep(0.2, 4.0 + 5.0 * n + 10.0 * surf, dw)) * (0.5 + 0.5 * surf);
	float ph = fract(dw / 22.0 + t * 0.08 + n * 0.25);  // fronts travel towards the shore
	float front = smoothstep(0.0, 0.05, ph) * (1.0 - smoothstep(0.05, 0.5, ph));
	float gate = smoothstep(0.3, 0.55, vnoise(en * vec2(0.035, 0.05) + 3.7 + vec2(t * 0.02, 0.0)));
	float lines = front * gate * (1.0 - smoothstep(25.0, 110.0, d)) * (0.55 + 0.45 * surf);
	return clamp(swash + lines, 0.0, 1.0) * k;
}
