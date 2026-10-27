shader_type sky;
// Sky: single-scattering Rayleigh + Mie + ozone atmosphere (atmo_sky, the twin of
// world/atmosphere.gd, which SkyTime samples for the fog colour), sun disk + Mie glow; at night
// stars and a phased moon (world/night_sky.gd). The gradient uniforms carry overcast, night and
// lightning; the analytic sky is blended in as its deviation from its own gradient (see sky()).
// (Clouds are a depth-aware full-screen pass: world/volumetric_clouds.gdshader.)

uniform vec3 zenith_color : source_color = vec3(0.25, 0.45, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.8, 0.9);
uniform vec3 ground_color : source_color = vec3(0.25, 0.27, 0.27);
uniform float day = 1.0;          // 0 night .. 1 day
uniform float dusk = 0.0;         // sunset tint amount (cirrus)
uniform vec3 model_top : source_color = vec3(0.25, 0.45, 0.85);      // atmosphere at the zenith / horizon
uniform vec3 model_hor : source_color = vec3(0.72, 0.8, 0.9);        // (what the gradient would be if clear)
uniform float clear = 0.0;        // 0 .. 1 weight of the analytic sky (0 under a deck: plain gradient)
uniform float atmo_gain = 1.0;    // twilight brightness lift (Atmosphere.twilight_gain)
uniform float aerosol = 1.0;      // haze amount (Atmosphere.aerosol_for_visibility)
uniform float sun_vis = 1.0;      // 0 = sun hidden behind a thick deck
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);  // render frame, towards the moon
uniform vec3 sun_dir_u = vec3(0.0, 1.0, 0.0);  // towards the sun (for the moon's phase)
uniform float moon_illum = 0.5;   // illuminated fraction
uniform float moon_vis = 0.0;     // night x clear sky x above the horizon
uniform float stars = 0.0;        // star visibility
uniform float cirrus = 0.0;       // 0..1 high wispy layer (thinner / absent under a thick deck)
uniform vec2 cirrus_wind = vec2(0.0);

// ---- single scattering atmosphere (constants and sample layout as in atmosphere.gd) ----
const float A_RE = 6371000.0;
const float A_TOP = 60000.0;
const float A_D_TOP = 2.0 * A_RE * A_TOP + A_TOP * A_TOP;
const float A_HR = 8000.0;
const float A_HM = 1200.0;
const float A_H0 = 300.0;
const float A_CAP = 80000.0;
const vec3 A_BR = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const vec3 A_BO = vec3(0.65e-6, 1.881e-6, 0.085e-6) * 1.5;
const float A_BM = 21e-6 * 0.1;
const float A_E = 30.0;

float a_height(float a) { return a / (sqrt(a + A_RE * A_RE) + A_RE); }
vec3 a_ext(float h, float bm) {
	float oz = max(1.0 - abs(h - 25000.0) / 15000.0, 0.0);
	return A_BR * exp(-h / A_HR) + vec3(bm / 0.9 * exp(-h / A_HM)) + A_BO * oz;
}

vec3 atmo_sky(vec3 dir, vec3 sun_in) {
	vec3 sun = normalize(vec3(sun_in.x, max(sun_in.y, 0.0), sun_in.z));  // below the horizon: on it
	vec3 d = normalize(vec3(dir.x, max(dir.y, 0.0), dir.z));
	float bm = A_BM * aerosol;
	float r0 = A_RE + A_H0;
	float a0 = 2.0 * A_RE * A_H0 + A_H0 * A_H0;
	float b0 = r0 * d.y;
	float tm = min(-b0 + sqrt(max(b0 * b0 - (a0 - A_D_TOP), 0.0)), A_CAP);
	float cg = dot(d, sun);
	float ph_r = 3.0 / (16.0 * PI) * (1.0 + cg * cg);
	const float G = 0.76;
	float ph_m = 3.0 / (8.0 * PI) * ((1.0 - G * G) * (1.0 + cg * cg)) / ((2.0 + G * G) * pow(1.0 + G * G - 2.0 * G * cg, 1.5));
	vec3 tv = vec3(0.0), sr = vec3(0.0), sm = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float u0 = float(i) / 8.0, u1 = float(i + 1) / 8.0;
		u0 *= u0; u1 *= u1;
		float t = tm * (u0 + u1) * 0.5, dt = tm * (u1 - u0);
		float a = a0 + 2.0 * b0 * t + t * t;
		float h = a_height(a);
		float rr = exp(-h / A_HR), rm = exp(-h / A_HM);
		tv += a_ext(h, bm) * dt;
		float ps = r0 * sun.y + t * cg;
		if (ps < 0.0 && a < ps * ps) continue;  // the planet shadows this sample
		float ts = -ps + sqrt(max(ps * ps - (a - A_D_TOP), 0.0));
		vec3 tsun = vec3(0.0);
		for (int j = 0; j < 4; j++) {
			float v0 = float(j) / 4.0, v1 = float(j + 1) / 4.0;
			v0 *= v0; v1 *= v1;
			float q = ts * (v0 + v1) * 0.5;
			float aq = max(a + 2.0 * ps * q + q * q, 0.0);
			tsun += a_ext(a_height(aq), bm) * (ts * (v1 - v0));
		}
		vec3 tr = exp(-(tv + tsun));
		sr += tr * (rr * dt);
		sm += tr * (rm * dt);
	}
	vec3 l = (sr * A_BR * ph_r + sm * (bm * ph_m)) * A_E * atmo_gain;
	float s = sqrt(clamp(d.y, 0.0, 1.0));  // saturation / exposure shaping (Atmosphere._finish)
	float luma = dot(l, vec3(0.2126, 0.7152, 0.0722));
	return max(vec3(luma) + (l - luma) * mix(0.8, 1.35, s), 0.0) * mix(0.55, 0.72, s);
}

// interleaved gradient noise, for dithering the 8-bit output
float ign(vec2 px) { return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715)))); }

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

vec3 star_field(vec3 d) {
	vec3 p = d * 260.0;
	vec3 id = floor(p);
	float h = hash3(id);
	if (h < 0.995) return vec3(0.0);
	vec3 c = id + 0.5 + (vec3(hash3(id + 1.3), hash3(id + 2.7), hash3(id + 5.1)) - 0.5) * 0.6;
	float r = length(p - c);
	float mag = pow((h - 0.995) / 0.005, 3.0);  // few bright, many faint
	vec3 tint = mix(vec3(0.8, 0.88, 1.0), vec3(1.0, 0.9, 0.75), hash3(id + 9.0));
	return tint * mag * 2.2 * exp(-r * r * 9.0);
}

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}
// cirrus: stretched streaks on a plane high above, fading out towards the horizon
float cirrus_density(vec3 d) {
	vec2 uv = d.xz / (d.y + 0.15) * 1.3 + cirrus_wind;
	vec2 q = vec2(uv.x * 0.45, uv.y * 2.4);
	float a = 0.0, w = 0.5;
	for (int i = 0; i < 4; i++) {
		a += w * n2(q);
		q = q * 2.07 + vec2(3.1, 1.7);
		w *= 0.5;
	}
	return smoothstep(0.5 - cirrus * 0.14, 0.82, a) * smoothstep(0.03, 0.28, d.y);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = LIGHT0_DIRECTION;  // towards the sun, render frame (x east, y up, z south)
	float up = max(d.y, 0.0);
	// analytic sky as a deviation from its own gradient: the weather / night colours in the
	// uniforms pass through unchanged, a clear day is exactly atmo_sky(). The radiance (ambient)
	// cubemap pass keeps the plain gradient.
	vec3 sun_u = normalize(sun_dir_u);
	float g = pow(up, 0.5);
	vec3 col = mix(horizon_color, zenith_color, g);
	if (clear > 0.001 && !AT_CUBEMAP_PASS) {
		col += clear * (atmo_sky(d, sun_u) - mix(model_hor, model_top, g));
	}
	if (d.y < 0.0) col = mix(col, ground_color, smoothstep(0.0, 0.2, -d.y));
	float mu = max(dot(d, sun), 0.0);
	col += LIGHT0_COLOR * (pow(mu, 2000.0) * 40.0 + pow(mu, 12.0) * 0.18 + pow(mu, 3.0) * 0.06) * LIGHT0_ENERGY * day * sun_vis;
	if (AT_CUBEMAP_PASS) {  // radiance / ambient: no point sources
		COLOR = col;
	} else {
		float above = smoothstep(-0.01, 0.06, d.y);  // extinction near the horizon
		if (cirrus > 0.0 && d.y > 0.0) {
			float dens = cirrus_density(d);
			vec3 lit = mix(vec3(0.88, 0.91, 0.97), vec3(1.0, 0.7, 0.5), dusk * 0.8) * (0.04 + 0.96 * day) + vec3(0.6, 0.68, 0.85) * 0.05 * moon_illum * moon_vis;
			lit *= 1.0 + 1.6 * pow(mu, 6.0) * day;  // silver lining towards the sun
			col = mix(col, lit, dens * cirrus * 0.6 * sun_vis);
		}
		if (stars > 0.0) col += star_field(d) * stars * above;
		if (moon_vis > 0.0) {
			// disc (0.6 deg radius, enlarged for readability) shaded by the sun's direction
			float R = 0.0105;
			vec3 v = d - moon_dir * dot(d, moon_dir);
			float r = length(v) / R;
			float md = dot(d, moon_dir);
			if (md > 0.0 && r < 1.0) {
				vec3 n = normalize(v / R + moon_dir * sqrt(1.0 - r * r) * -1.0);
				float lit = smoothstep(-0.05, 0.12, dot(n, sun_dir_u));
				float edge = 1.0 - smoothstep(0.85, 1.0, r);
				col = mix(col, vec3(0.9, 0.92, 0.95) * (0.04 + 1.4 * lit), edge * moon_vis * above);
			}
			float mm = max(md, 0.0);
			col += vec3(0.6, 0.68, 0.85) * (pow(mm, 3000.0) * 0.1 + pow(mm, 60.0) * 0.05) * moon_illum * moon_vis;
		}
		// dither: a dark smooth gradient quantised to 8 bits shows concentric bands; +-4 % noise
		// (about one output level at night brightness) breaks them up
		COLOR = col * (1.0 + (ign(FRAGCOORD.xy) + ign(FRAGCOORD.yx + 17.0) - 1.0) * 0.08);
	}
}
