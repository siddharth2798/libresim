shader_type spatial;
// Follow-me car body (world/follow_me_shell.gd, follow_me_wheel.gd). One shader for every opaque part:
// the vertex colour carries the albedo (rgb, linear) and the material kind (a * 10):
//   0 glossy paint (clearcoat, panel gaps, dirt)   1 matte plastic     2 rubber (tread)   3 metal
//   4 reflective tape   5 sign board (chequered border)   6 / 7 amber beacon lens left / right
//   8 headlamp lens     9 tail lamp lens
// Haze is applied here (aerial perspective, as terminal.gdshader) so the car fades into the same
// horizon as the terrain and the sky.
render_mode fog_disabled;

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;

uniform float night = 0.0;       // 0 day .. 1 night
uniform float head_glow = 0.0;   // headlamp emission
uniform float tail_glow = 0.2;   // tail lamp emission (0.2 lamps, 1 brake)
uniform float amber_l = 0.0;     // beacon lens emission, left / right
uniform float amber_r = 0.0;
uniform vec2 sign_size = vec2(1.30, 0.42);
uniform float dirt = 0.6;
uniform float panel_gaps = 1.0;  // door / hood gap lines (the pickup's; other vehicles switch them off)

varying vec3 v_pos;
varying vec3 v_nl;
varying float v_dist;

void vertex() {
	v_pos = VERTEX;
	v_nl = NORMAL;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float gap_line(float d) { return 1.0 - smoothstep(0.0012, 0.0035, d); }

void fragment() {
	int kind = int(COLOR.a * 10.0 + 0.5);
	vec3 col = COLOR.rgb;
	vec3 emit = vec3(0.0);
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.4;
	float cc = 0.0;
	float ccr = 0.08;
	float haze = 1.0 - exp(-v_dist * haze_density);

	if (kind == 0) {
		// panel gaps: doors on the sides, hood and tailgate on top / rear
		float gaps = 0.0;
		if (abs(v_nl.x) > 0.7 && v_pos.y > 0.42 && v_pos.y < 1.09) {
			gaps = max(gap_line(abs(v_pos.z + 0.98)), max(gap_line(abs(v_pos.z + 0.12)), gap_line(abs(v_pos.z - 0.80))));
		}
		if (v_nl.y > 0.6 && abs(v_pos.x) < 0.93) {
			gaps = max(gaps, max(gap_line(abs(v_pos.z + 1.02)), gap_line(abs(v_pos.z + 2.26))));
			gaps = max(gaps, gap_line(abs(v_pos.x)) * step(v_pos.z, -1.0));
		}
		// dirt: road film low on the body, vertical streaks, a little everywhere
		float low = smoothstep(0.95, 0.30, v_pos.y);
		float n1 = vnoise(vec2(v_pos.z * 4.0 + v_pos.x * 2.5, v_pos.y * 1.6));
		float n2 = vnoise(v_pos.xz * 21.0 + v_pos.y * 9.0);
		float dm = clamp(dirt * (low * (0.25 + 0.55 * n1) + 0.03 * n2 + 0.04), 0.0, 0.75);
		col = mix(col, vec3(0.20, 0.155, 0.10), dm);
		col *= 1.0 - 0.8 * gaps * panel_gaps;
		col = mix(col, vec3(0.012), smoothstep(-0.25, -0.6, v_nl.y));  // underside / headliner
		rough = mix(0.32, 0.85, dm);
		spec = 0.5;
		cc = 1.0 - clamp(dm * 1.6 + gaps * panel_gaps, 0.0, 1.0);
		ccr = 0.05;
	} else if (kind == 1) {
		float n = vnoise(v_pos.xz * 17.0 + v_pos.y * 5.0);
		col *= 0.9 + 0.2 * n;
		rough = 0.62;
		spec = 0.35;
	} else if (kind == 2) {
		float tread = 1.0 - smoothstep(0.4, 0.7, abs(v_nl.x));
		float groove = step(0.78, fract(UV.x * 36.0)) * tread;
		float rib = (1.0 - smoothstep(0.0, 0.03, abs(UV.y - 0.5))) * tread;
		col = col * (1.0 - 0.55 * max(groove, rib)) + vec3(0.03, 0.028, 0.025) * (0.3 + tread * 0.7);
		rough = 0.93;
		spec = 0.15;
	} else if (kind == 3) {
		metal = 0.85;
		rough = 0.38 + 0.1 * vnoise(v_pos.yz * 40.0);
		spec = 0.6;
	} else if (kind == 4) {
		rough = 0.22;
		spec = 0.9;
		emit = col * night * 0.05;
	} else if (kind == 5) {
		vec2 s = UV * sign_size;
		float b = 0.047;
		vec2 edge = min(s, sign_size - s);
		float border = step(min(edge.x, edge.y), b * 2.0);
		float chk = mod(floor(s.x / b) + floor(s.y / b), 2.0);
		col = border > 0.5 ? mix(col, vec3(0.012), chk) : col;
		emit = col * night * 0.3;  // the board is lit at night
		rough = 0.45;
	} else if (kind == 6 || kind == 7) {
		float e = kind == 6 ? amber_l : amber_r;
		vec3 amber = vec3(1.0, 0.42, 0.03);
		col = mix(col, amber * 0.6, 0.3);
		emit = amber * (0.12 + 3.0 * e);
		rough = 0.12;
		spec = 0.8;
	} else if (kind == 8) {
		col = vec3(0.55, 0.58, 0.6);
		emit = vec3(1.0, 0.95, 0.82) * head_glow * 3.0;
		rough = 0.05;
		spec = 0.9;
	} else if (kind == 9) {
		emit = vec3(1.0, 0.05, 0.02) * (0.06 + tail_glow * 2.6);
		rough = 0.1;
		spec = 0.8;
	}
	col *= mix(1.0, 0.8, wetness);
	ALBEDO = col * (1.0 - haze);
	EMISSION = emit * (1.0 - haze * 0.5) + fog_color * haze;
	ROUGHNESS = mix(rough, rough * 0.5, wetness * 0.6);
	SPECULAR = spec * (1.0 - haze);
	METALLIC = metal;
	CLEARCOAT = cc * (1.0 - haze);
	CLEARCOAT_ROUGHNESS = ccr;
}
