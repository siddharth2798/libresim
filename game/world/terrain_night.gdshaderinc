// Night ground for terrain.gdshader (after hash / vnoise / terrain_roads): the ground itself goes dark and
// colourless (scotopic vision, no blotchy macro tones lit by a blue ambient), and two kinds of light are added:
//   street lighting: sodium-orange pools along the road ribbons (only where the road SDF is bound, ~3.4 km),
//   city lights: a sparse speckle of point lights over WorldCover built-up land, so a far city reads as a carpet
//   of points. Points are energy-conserving and never smaller than ~1 px; once a cell is under a few pixels the
//   speckle becomes its average glow (no shimmer). Colours and brightness match building_night.gdshaderinc.

global uniform float night_level;  // 0 day .. 1 night (NightSky)

const float NIGHT_DESAT = 0.55;     // colour removed from the ground albedo at full night
const float ROAD_EMIT = 0.05;       // lit asphalt under the lamps (linear)
const float ROAD_LAMP_M = 30.0;     // street lamp spacing
const float CITY_EMIT = 1.1;        // core of a ground light point
const float CITY_CELL_M = 16.0;     // one candidate light per cell
const float CITY_DENSITY = 0.42;    // share of cells with a light (mean; neighbourhoods vary)
const vec3 SODIUM = vec3(1.0, 0.48, 0.14);

// ground albedo at night: less saturated, macro tonal blotches flattened by the caller
vec3 night_albedo(vec3 col) {
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	return mix(col, vec3(l), NIGHT_DESAT * night_level);
}

vec3 city_lamp(float r) {
	if (r < 0.55) return SODIUM;               // sodium street lamps
	if (r < 0.85) return vec3(0.85, 0.9, 1.0);  // white LED
	return vec3(1.0, 0.74, 0.45);               // warm windows, shop signs
}

// Speckled city lights over built-up land. en: world east/north (m), aa: pixel footprint (m).
vec3 city_lights(vec2 en, float aa, float built) {
	if (built <= 0.01) {
		return vec3(0.0);
	}
	float dens = CITY_DENSITY * mix(0.35, 1.6, smoothstep(0.2, 0.8, vnoise(en * 0.0035 + 3.1)));  // brighter and darker quarters
	vec3 avg_col = SODIUM * 0.55 + vec3(0.85, 0.9, 1.0) * 0.3 + vec3(1.0, 0.74, 0.45) * 0.15;
	const float R0 = 1.4;  // m, physical size of a point's bright core
	float area = 3.14159 * R0 * R0 * 0.5;  // integral of the soft disc below / pi r^2 ~ 0.5
	vec3 avg = avg_col * dens * CITY_EMIT * area / (CITY_CELL_M * CITY_CELL_M) * 0.6;  // 0.6: mean brightness
	float far_k = smoothstep(CITY_CELL_M * 0.18, CITY_CELL_M * 0.4, aa);
	vec3 pts = vec3(0.0);
	if (far_k < 1.0) {
		vec2 c = floor(en / CITY_CELL_M);
		float hp = hash(c + 5.1);
		if (hp < dens) {
			vec2 lp = (c + 0.15 + 0.7 * vec2(hash(c), hash(c + 17.3))) * CITY_CELL_M;
			float r = max(R0, aa * 0.8);
			float d = length(en - lp) / r;
			float disc = max(1.0 - d * d, 0.0);
			float bright = mix(0.3, 1.0, hash(c + 9.7));
			pts = city_lamp(hash(c + 2.3)) * disc * bright * CITY_EMIT * (R0 * R0) / (r * r);
		}
	}
	return mix(pts, avg, far_k) * built;
}

// Sodium light on lit road ribbons. road: ribbon cover 0..1, e: m from the ribbon edge, aa: pixel footprint (m)
vec3 street_light(vec2 en, float road, int cls, float e, float aa) {
	if (cls <= 0 || cls > 8) {
		return vec3(0.0);
	}
	float major = cls <= 5 ? 1.0 : (cls == 8 ? 0.35 : 0.7);
	float pool = 0.0;
	for (int j = 0; j <= 1; j++) {
		for (int i = 0; i <= 1; i++) {
			vec2 cc = floor(en / ROAD_LAMP_M - 0.5) + vec2(float(i), float(j));
			vec2 lp = (cc + 0.5 + 0.3 * (vec2(hash(cc), hash(cc + 3.7)) - 0.5)) * ROAD_LAMP_M;
			float d = length(en - lp);
			pool = max(pool, exp(-d * d / (2.0 * 9.0 * 9.0)));
		}
	}
	pool = mix(pool, 0.45, smoothstep(4.0, 14.0, aa));  // far: the average of the pools
	float spill = (1.0 - smoothstep(0.0, 4.0, e)) * (1.0 - road) * 0.35;  // light beside the road
	return SODIUM * ROAD_EMIT * major * (road + spill) * (0.25 + 0.75 * pool);
}
