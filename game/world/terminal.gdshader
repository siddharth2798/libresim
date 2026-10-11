shader_type spatial;
// Landmark airport terminals (tools/16_terminal_models.py -> world/terminals.gd).
// One shader, material "kind" chosen by the glb material name:
//   0 glass curtain wall (mullion grid, sky reflection, interior lit at night)
//   1 solid panels (cladding joints)          2 metal roof (standing seams)
//   3 clay-tile roof (Kerala, tile rows)      4 plain concrete / columns
//   5 coffered soffit (canopy underside, downlights at night)
render_mode cull_disabled, fog_disabled;

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;
global uniform vec2 pattern_origin;  // origin mod ~50 km (float32-safe)
global uniform vec3 sky_top_color;

uniform int kind = 1;
uniform vec3 base_color : source_color = vec3(0.8);
uniform float mullion = 1.6;   // m between vertical mullions
uniform float floor_h = 4.5;   // m between transoms / floors
uniform float night = 0.0;

varying vec3 v_world;   // x east, y up, z = -north, relative to the pattern wrap base
varying vec3 v_n;
varying float v_dist;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world = w + vec3(pattern_origin.x, 0.0, -pattern_origin.y);
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 n = normalize(v_n);
	// horizontal facade coordinate along the wall
	float u = dot(v_world.xz, normalize(vec2(-n.z, n.x) + 1e-5));
	float far = smoothstep(600.0, 2200.0, v_dist);
	vec3 col = base_color;
	vec3 emit = vec3(0.0);
	float rough = 0.8;
	float metal = 0.0;
	if (kind == 0) {
		vec2 cell = vec2(u / mullion, v_world.y / floor_h);
		vec2 f = fract(cell);
		float frame = max(step(f.x, 0.06), step(f.y, 0.035));
		float slab_band = step(0.93, f.y);  // floor edge behind the glass
		float fres = pow(1.0 - abs(dot(normalize(VIEW), NORMAL)), 3.0);
		vec3 refl = mix(fog_color, sky_top_color, 0.35 + 0.4 * n.y);
		vec3 glass = mix(base_color * 0.35, refl, 0.35 + 0.55 * fres);
		col = mix(glass, vec3(0.75, 0.77, 0.78), max(frame, slab_band * 0.6) * (1.0 - far));
		float lit = (0.6 + 0.4 * hash(floor(cell * vec2(0.25, 1.0)))) * (1.0 - frame);
		emit = vec3(1.0, 0.88, 0.68) * lit * night * 0.35;
		rough = 0.08;
		metal = 0.4;
	} else if (kind == 1) {
		vec2 f = fract(vec2(u / 3.0, v_world.y / 1.5));
		float joint = max(step(f.x, 0.012), step(f.y, 0.02)) * (1.0 - far);
		col = base_color * (1.0 - 0.18 * joint);
		rough = 0.6;
	} else if (kind == 2) {
		float s = fract((v_world.x * 0.7 + v_world.z * 0.7) / 0.9);
		col = base_color * (0.94 + 0.06 * step(0.9, s) * (1.0 - far));
		rough = 0.45;
		metal = 0.3;
	} else if (kind == 3) {
		// clay tiles: courses along the slope, staggered joints
		float course = v_world.y / 0.28;
		float row = floor(course);
		float joint = fract(u / 0.32 + 0.5 * mod(row, 2.0));
		float shade = 0.82 + 0.18 * smoothstep(0.0, 0.8, fract(course));
		col = base_color * shade * (1.0 - 0.25 * step(0.93, joint)) * (0.9 + 0.2 * hash(vec2(row, floor(u / 0.32))));
		col = mix(col, base_color * 0.9, far);
		rough = 0.9;
	} else if (kind == 5) {
		vec2 f = fract(v_world.xz / 6.0);
		float rib = max(step(f.x, 0.08), step(f.y, 0.08));
		col = base_color * (0.85 + 0.15 * rib);
		float spot = 1.0 - smoothstep(0.05, 0.12, length(f - 0.5));
		emit = vec3(1.0, 0.92, 0.78) * spot * night * 0.8;
	}
	col *= mix(1.0, 0.8, wetness);
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = emit * (1.0 - haze * 0.5) + fog_color * haze;
	ROUGHNESS = mix(rough, rough * 0.5, wetness);
	SPECULAR = 0.5 * (1.0 - haze);
	METALLIC = metal;
}
