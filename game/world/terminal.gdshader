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
#include "res://world/curvature.gdshaderinc"  // Earth curvature (G4)
#include "res://world/haze_sky.gdshaderinc"  // view-dependent haze colour (G4)
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
	VERTEX += curve_local(MODEL_MATRIX, curve_drop(w));
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Share of a pixel covered by lines that fill [0, w) of every period of x (x in periods), box-filtered over the
// pixel's footprint. A hard step() here turned 1-7 cm mullions, joints and seams into moire that crawled and
// waved as the camera moved; filtered, a line thinner than a pixel becomes its average shade instead.
float line_cov(float x, float w) {
	float fw = max(fwidth(x), 1e-4);
	float a = x - 0.5 * fw;
	float b = x + 0.5 * fw;
	float ca = floor(a) * w + min(fract(a), w);
	float cb = floor(b) * w + min(fract(b), w);
	return clamp((cb - ca) / fw, 0.0, 1.0);
}

// 1 up close, 0 once a pattern of this period (x in periods) is under ~3 pixels: its fine shading goes flat.
float detail_of(float x) {
	return 1.0 - smoothstep(0.15, 0.35, fwidth(x));
}

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
		float frame = max(line_cov(cell.x, 0.06), line_cov(cell.y, 0.035));
		float slab_band = line_cov(cell.y - 0.93, 0.07);  // floor edge behind the glass
		float fres = pow(1.0 - abs(dot(normalize(VIEW), NORMAL)), 3.0);
		vec3 refl = mix(fog_color, sky_top_color, 0.35 + 0.4 * n.y);
		vec3 glass = mix(base_color * 0.35, refl, 0.35 + 0.55 * fres);
		col = mix(glass, vec3(0.75, 0.77, 0.78), max(frame, slab_band * 0.6) * (1.0 - far));
		// lit interior: bays of four panels vary, brighter under each floor's ceiling lights
		float bay_d = detail_of(cell.x * 0.25);
		float lit = mix(0.8, mix(0.6, 1.0, hash(floor(cell * vec2(0.25, 1.0)))), bay_d) * mix(0.85, 0.7 + 0.3 * smoothstep(0.2, 0.9, f.y), detail_of(cell.y)) * (1.0 - frame);
		emit = vec3(1.0, 0.84, 0.62) * lit * night * 0.26;
		rough = 0.08;
		metal = 0.4;
	} else if (kind == 1) {
		float joint = max(line_cov(u / 3.0, 0.012), line_cov(v_world.y / 1.5, 0.02)) * (1.0 - far);
		col = base_color * (1.0 - 0.18 * joint);
		rough = 0.6;
	} else if (kind == 2) {
		float seam = (v_world.x * 0.7 + v_world.z * 0.7) / 0.9;
		col = base_color * (0.94 + 0.06 * line_cov(seam - 0.9, 0.1) * (1.0 - far));
		rough = 0.45;
		metal = 0.3;
	} else if (kind == 3) {
		// clay tiles: courses along the slope, staggered joints
		float course = v_world.y / 0.28;
		float row = floor(course);
		float jx = u / 0.32 + 0.5 * mod(row, 2.0);
		float d = min(detail_of(course), detail_of(u / 0.32));  // tiles under ~3 px: their average, not noise
		float shade = mix(0.93, 0.82 + 0.18 * smoothstep(0.0, 0.8, fract(course)), d);
		float joint = line_cov(jx - 0.93, 0.07) * d;  // the stagger jumps at each course: d hides the bad derivative
		col = base_color * shade * (1.0 - 0.25 * joint) * mix(1.0, 0.9 + 0.2 * hash(vec2(row, floor(u / 0.32))), d);
		col = mix(col, base_color * 0.9, far);
		rough = 0.9;
	} else if (kind == 5) {
		vec2 f = fract(v_world.xz / 6.0);
		float rib = max(line_cov(v_world.x / 6.0, 0.08), line_cov(v_world.z / 6.0, 0.08));
		col = base_color * (0.85 + 0.15 * rib);
		float spot = 1.0 - smoothstep(0.05, 0.12, length(f - 0.5));
		emit = vec3(1.0, 0.92, 0.78) * spot * night * 0.8;
	}
	col *= mix(1.0, 0.8, wetness);
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = emit * (1.0 - haze * 0.5) + haze_color(-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * haze;
	ROUGHNESS = mix(rough, rough * 0.5, wetness);
	SPECULAR = 0.5 * (1.0 - haze);
	METALLIC = metal;
}
