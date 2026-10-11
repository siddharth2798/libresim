shader_type spatial;
render_mode fog_disabled;  // haze is applied below (aerial perspective, as terrain.gdshader)
// OSM buildings: flat-shaded extruded footprints (tools/10_buildings.py).
// CUSTOM0 = roof colour (rgb, from satellite imagery) + facade style (a).
// Walls get a procedural facade: floor bands + window grid, windows lit at night.

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;
global uniform vec2 pattern_origin;  // FloatingOrigin: origin mod ~50 km (float32-safe)
uniform float night = 0.0;  // 0 day .. 1 night (set by Buildings from the sun)

varying vec4 v_custom;
varying vec3 v_world;
varying float v_dist;

void vertex() {
	v_custom = CUSTOM0;
	// world-stable facade coordinates (no window jump on a floating-origin shift)
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + vec3(pattern_origin.x, 0.0, -pattern_origin.y);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 n_world = normalize(cross(dFdx(v_world), dFdy(v_world)));
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float style = v_custom.a;
	vec3 roof = v_custom.rgb;
	vec3 col;
	vec3 emit = vec3(0.0);
	if (abs(n_world.y) > 0.7) {
		// roof: imagery colour, a bit brighter (imagery is dark & hazy)
		col = pow(roof, vec3(0.85)) * 1.2;
	} else {
		// wall: palette by style, tinted slightly toward the roof colour
		// Mumbai/Pune palette: weathered concrete, cream, pastel and stained greys
		vec3 pal = mix(vec3(0.58, 0.56, 0.52), vec3(0.74, 0.70, 0.60), fract(style * 7.0));
		pal = mix(pal, vec3(0.50, 0.53, 0.56), step(0.65, fract(style * 3.0)));
		pal = mix(pal, vec3(0.72, 0.62, 0.52), step(0.85, fract(style * 5.0)));
		// monsoon staining: darker toward the ground
		pal *= mix(0.78, 1.0, smoothstep(0.0, 12.0, fract(v_world.y / 40.0) * 40.0));
		col = mix(pal, roof * 1.4, 0.15);
		// facade coordinate along the wall (pick the horizontal axis by wall facing)
		float u = abs(n_world.x) > abs(n_world.z) ? v_world.z : v_world.x;
		float floor_h = 3.1;
		vec2 cell = vec2(u / 2.6, v_world.y / floor_h);
		vec2 f = fract(cell);
		float window = step(0.2, f.x) * step(f.x, 0.8) * step(0.3, f.y) * step(f.y, 0.78);
		// anti-alias: once a window is under ~3 px, draw its average instead of the pattern,
		// so distant facades and city lights don't shimmer or blink as the camera moves
		vec2 fw = fwidth(cell);
		float detail = 1.0 - smoothstep(0.2, 0.45, max(fw.x, fw.y));
		const float COVER = 0.6 * 0.48;  // window area fraction of a cell
		float glass_dark = mix(0.35, 0.55, fract(style * 13.0));
		float win = mix(COVER, window, detail);
		col = mix(col, col * glass_dark + vec3(0.03, 0.05, 0.07), win * 0.85);
		// night: per-building occupancy (offices mostly dark, homes warmer), soft warm/cool lamps
		float occ = mix(0.06, 0.3, fract(style * 17.0));
		float on = step(1.0 - occ, hash(floor(cell) + style * 31.0));
		vec3 lamp = mix(vec3(1.0, 0.76, 0.48), vec3(0.82, 0.88, 1.0), step(0.8, fract(style * 23.0)));
		float lit = mix(occ * COVER, on * window, detail) * night;
		emit = lamp * lit * 0.75;
		// fade the facade colour pattern out with distance
		float far = smoothstep(800.0, 2500.0, v_dist);
		col = mix(col, mix(pal, roof, 0.2) * 0.9, far);
	}
	col *= mix(1.0, 0.72, wetness);
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = emit * (1.0 - haze * 0.5) + fog_color * haze;
	ROUGHNESS = mix(0.85, 0.4, wetness);
	SPECULAR = 0.5 * (1.0 - haze);
}
