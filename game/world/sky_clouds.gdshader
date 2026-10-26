shader_type sky;
// Sky: scattering-style gradient with sunset tint, sun disk + Mie glow; at night stars and
// a phased moon (world/night_sky.gd).
// (Clouds are a depth-aware full-screen pass: world/volumetric_clouds.gdshader.)

uniform vec3 zenith_color : source_color = vec3(0.25, 0.45, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.8, 0.9);
uniform vec3 ground_color : source_color = vec3(0.25, 0.27, 0.27);
uniform float day = 1.0;          // 0 night .. 1 day
uniform float dusk = 0.0;         // sunset tint amount
uniform float sun_vis = 1.0;      // 0 = sun hidden behind a thick deck
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);  // render frame, towards the moon
uniform vec3 sun_dir_u = vec3(0.0, 1.0, 0.0);  // towards the sun (for the moon's phase)
uniform float moon_illum = 0.5;   // illuminated fraction
uniform float moon_vis = 0.0;     // night x clear sky x above the horizon
uniform float stars = 0.0;        // star visibility
uniform float cirrus = 0.0;       // 0..1 high wispy layer (thinner / absent under a thick deck)
uniform vec2 cirrus_wind = vec2(0.0);

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
	vec3 hor = mix(horizon_color, vec3(1.0, 0.62, 0.42), dusk * pow(1.0 - up, 6.0) * max(dot(normalize(d.xz), normalize(sun.xz)), 0.0));
	vec3 col = mix(hor, zenith_color, pow(up, 0.5));
	if (d.y < 0.0) col = mix(hor, ground_color, smoothstep(0.0, 0.2, -d.y));
	float mu = max(dot(d, sun), 0.0);
	col += LIGHT0_COLOR * (pow(mu, 2000.0) * 40.0 + pow(mu, 12.0) * 0.18 + pow(mu, 3.0) * 0.06) * LIGHT0_ENERGY * day * sun_vis;
	if (AT_CUBEMAP_PASS) {  // radiance / ambient: no point sources
		COLOR = col;
	} else {
		float above = smoothstep(-0.01, 0.06, d.y);  // extinction near the horizon
		if (cirrus > 0.0 && d.y > 0.0) {
			float dens = cirrus_density(d);
			vec3 lit = mix(vec3(0.88, 0.91, 0.97), vec3(1.0, 0.7, 0.5), dusk * 0.8) * (0.2 + 0.8 * day);
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
		COLOR = col;
	}
}
