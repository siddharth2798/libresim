// Shared surface model of the procedural ground vehicles (world/vehicle.gdshader) and the follow-me car
// (world/follow_me.gdshader). The vertex colour carries the albedo (rgb, linear) and the kind (a * 10):
//   0 glossy paint (clearcoat, dirt, dust, worn edges)   1 matte plastic   2 rubber (tread)   3 metal
//   4 retro-reflective tape   5 sign board (chequered border)   6 / 7 amber beacon lens left / right
//   8 headlamp lens   9 tail lamp lens   10 fleet-number plate (three digits from the vehicle's seed)
// Weathering is procedural in vehicle space: road film and splash low on the body, dust on top faces,
// rain streaks, chipped paint on rounded edges, a darker tone near the ground (cheap AO). Fine detail
// fades out with distance so far vehicles do not shimmer.

uniform float night = 0.0;       // 0 day .. 1 night
uniform float head_glow = 0.0;   // headlamp emission
uniform float tail_glow = 0.2;   // tail lamp emission (0.2 lamps, 1 brake)
uniform float amber_l = 0.0;     // beacon lens emission without a pivot (light bar), left / right
uniform float amber_r = 0.0;
uniform vec2 sign_size = vec2(1.30, 0.42);
uniform float dirt = 0.6;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 3 x 5 digit glyphs, rows top to bottom, 3 bits each
const int GLYPH[10] = int[](31599, 11415, 29671, 29647, 23497, 31183, 31215, 29330, 31727, 31695);

float digits3(vec2 uv, float seed) {
	float u = uv.x * 12.6 - 0.8;
	float v = (1.0 - uv.y) * 7.0 - 1.0;
	int cell = int(floor(u / 4.0));
	int cx = int(floor(mod(u, 4.0)));
	int row = int(floor(v));
	if (u < 0.0 || cell > 2 || cx > 2 || row < 0 || row > 4) return 0.0;
	int n = int(floor(seed * 997.0)) % 1000;
	int d = cell == 0 ? n / 100 : (cell == 1 ? (n / 10) % 10 : n % 10);
	return float((GLYPH[d] >> ((4 - row) * 3 + (2 - cx))) & 1);
}

// Rotating beacon: lit side of the lens turning at ~80 rpm, a strong flash when the beam faces the eye.
float beacon_level(vec3 p, vec4 piv, vec3 to_eye, float phase) {
	float a0 = TIME * 8.4 + phase * 6.2832;
	vec2 beam = vec2(sin(a0), cos(a0));
	vec2 d = normalize(p.xz - piv.xz + vec2(1e-4, 0.0));
	float lit = pow(0.5 + 0.5 * dot(d, beam), 5.0);
	float face = pow(max(dot(beam, normalize(to_eye.xz + vec2(1e-4, 0.0))), 0.0), 14.0);
	return lit * 1.2 + face * 2.5;
}

// p, nl: vehicle-space position / normal; to_eye: vehicle-space direction to the camera; piv: CUSTOM0;
// seed: per vehicle 0..1; lamps: 0 parked (lamps off) .. 1 working (beacon turning, headlamps at night).
void vehicle_surface(int kind, vec3 p, vec3 nl, vec2 uv, vec4 piv, vec3 to_eye, float dist, float seed, float lamps,
		inout vec3 col, out vec3 emit, out float rough, out float metal, out float spec, out float cc, out float ccr, out float ao) {
	emit = vec3(0.0);
	rough = 0.6;
	metal = 0.0;
	spec = 0.4;
	cc = 0.0;
	ccr = 0.08;
	float detail = 1.0 - smoothstep(35.0, 160.0, dist);  // fine noise fades with distance
	float dirt_k = dirt * (0.7 + 0.6 * fract(seed * 7.31));
	float low = smoothstep(1.1, 0.15, p.y);
	float n1 = vnoise(vec2(p.z * 3.0 + p.x * 2.1, p.y * 1.3));
	float n2 = mix(0.5, vnoise(p.xz * 19.0 + p.y * 11.0), detail);
	float streak = mix(0.5, vnoise(vec2((p.z + p.x) * 9.0, p.y * 0.7)), detail);
	float up = smoothstep(0.55, 0.95, nl.y);
	ao = mix(0.62, 1.0, smoothstep(0.0, 0.75, p.y)) * mix(1.0, 0.55, smoothstep(-0.2, -0.7, nl.y));
	vec3 mud = vec3(0.23, 0.18, 0.12);
	vec3 dust = vec3(0.50, 0.44, 0.34);

	if (kind == 0) {
		// worn edges where the surface curves tightly (bevels, rounded corners; not a big tank radius)
		float curv = length(fwidth(nl)) / max(length(fwidth(p)), 1e-4);
		float edge = smoothstep(7.0, 22.0, curv) * detail;
		float chips = edge * smoothstep(0.55, 0.8, vnoise(p.xy * 31.0 + p.z * 17.0));
		float dm = clamp(dirt_k * (low * (0.22 + 0.55 * n1) + 0.07 * streak * (1.0 - up)), 0.0, 0.8);
		float dd = clamp(dirt_k * up * (0.10 + 0.25 * n1), 0.0, 0.5);
		col *= 0.96 + 0.08 * fract(seed * 3.7);  // fleet variation: older / newer paint
		col = mix(col, mud, dm);
		col = mix(col, dust, dd);
		col = mix(col, vec3(0.2, 0.2, 0.2), chips * 0.6);
		col = mix(col, vec3(0.012), smoothstep(-0.25, -0.6, nl.y));  // underside
		rough = mix(0.30, 0.85, max(dm, dd)) + chips * 0.3;
		spec = 0.5;
		cc = 1.0 - clamp(max(dm, dd) * 1.6 + chips, 0.0, 1.0);
		ccr = 0.06;
	} else if (kind == 1) {
		col *= 0.88 + 0.24 * n2;
		col = mix(col, mud, clamp(dirt_k * low * 0.45 * n1, 0.0, 0.5));
		col = mix(col, dust, clamp(dirt_k * up * 0.4, 0.0, 0.5));
		rough = 0.66;
		spec = 0.35;
	} else if (kind == 2) {
		float tread = 1.0 - smoothstep(0.4, 0.7, abs(nl.x));
		float groove = step(0.78, fract(uv.x * 36.0)) * tread * detail;
		float rib = (1.0 - smoothstep(0.0, 0.03, abs(uv.y - 0.5))) * tread * detail;
		col = col * (1.0 - 0.55 * max(groove, rib)) + vec3(0.03, 0.028, 0.025) * (0.3 + tread * 0.7);
		col = mix(col, dust * 0.5, clamp(dirt_k * (0.25 + 0.3 * n1) * (1.0 - tread), 0.0, 0.4));  // dusty sidewalls
		rough = 0.93;
		spec = 0.15;
	} else if (kind == 3) {
		float lum = dot(col, vec3(0.33));
		metal = 0.85;
		rough = mix(0.5, 0.16, smoothstep(0.2, 0.6, lum)) + 0.12 * n2;  // bright = polished / chrome
		col = mix(col, mud * 0.8, clamp(dirt_k * low * 0.5 * n1, 0.0, 0.5));
		spec = 0.6;
	} else if (kind == 4) {
		rough = 0.22;
		spec = 0.9;
		float retro = pow(max(dot(normalize(nl), normalize(to_eye)), 0.0), 4.0);  // shines back toward the eye
		emit = col * night * (0.04 + 0.25 * retro);
		col = mix(col, mud, clamp(dirt_k * low * 0.35, 0.0, 0.4));
	} else if (kind == 5) {
		vec2 s = uv * sign_size;
		float b = 0.047;
		vec2 e = min(s, sign_size - s);
		float border = step(min(e.x, e.y), b * 2.0);
		float chk = mod(floor(s.x / b) + floor(s.y / b), 2.0);
		col = border > 0.5 ? mix(col, vec3(0.012), chk) : col;
		emit = col * night * 0.3;
		rough = 0.45;
	} else if (kind == 6 || kind == 7) {
		vec3 amber = vec3(1.0, 0.42, 0.03);
		float e;
		if (piv.w >= 99.0) {
			e = lamps * beacon_level(p, piv, to_eye, seed + (kind == 7 ? 0.5 : 0.0)) * (0.5 + 0.5 * night);
		} else {
			e = kind == 6 ? amber_l : amber_r;
		}
		col = mix(col, amber * 0.6, 0.3);
		emit = amber * (0.06 + 3.0 * e);
		rough = 0.12;
		spec = 0.8;
	} else if (kind == 8) {
		col = vec3(0.55, 0.58, 0.6);
		emit = vec3(1.0, 0.95, 0.82) * head_glow * 3.0;
		rough = 0.05;
		spec = 0.9;
	} else if (kind == 9) {
		emit = vec3(1.0, 0.05, 0.02) * (0.04 + tail_glow * 2.6);
		rough = 0.1;
		spec = 0.8;
	} else if (kind == 10) {
		float ink = digits3(uv, seed);
		col = mix(col, vec3(0.015), mix(0.25, ink, detail));
		col = mix(col, mud, clamp(dirt_k * low * 0.3, 0.0, 0.3));
		rough = 0.5;
		emit = col * night * 0.03;
	}
}
