shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Rain on the canopy glass (next pass of the exterior glass material, see C172Model.fix_glass).
// Drops are laid out in the glass plane in model coordinates (glb frame: x aft, y up, z left):
// "flow" is the airflow direction along the surface (aft projected onto the glass), so on
// the windshield drops run up and back, on the side windows aft. Parked: beads sit and come
// and go; with airspeed they run back and stretch into streaks. Lit (sun/sky highlights)
// through a perturbed normal; a thin wet film lowers the contrast of the view outside.

global uniform float precip;          // local rain rate 0..1 (WeatherFx)
global uniform float rain_airspeed;   // m/s
global uniform vec3 fog_color;

varying vec3 v_pos;
varying vec3 v_n;

void vertex() {
	v_pos = VERTEX;
	v_n = NORMAL;
}

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// One layer of drops in cells of `cell` (m) stretched along the flow. Returns mask + gradient.
vec3 drops(vec2 q, float cell, float density, float move, float stretch, float seed) {
	vec2 cs = vec2(cell, cell * (1.0 + stretch));
	float lane = floor(q.x / cs.x);
	float lane_speed = 0.6 + 0.8 * hash2(vec2(lane, seed));
	q.y -= TIME * move * lane_speed;
	vec2 id = floor(q / cs);
	vec2 f = fract(q / cs) - 0.5;
	float h = hash2(id + seed);
	if (h > density) return vec3(0.0);
	float h2 = hash2(id * 1.73 + seed + 3.1);
	vec2 c = (vec2(h2, fract(h * 13.7)) - 0.5) * 0.45;
	float r = mix(0.1, 0.24, fract(h * 91.3));
	float life = fract(TIME * (0.12 + move * 0.4) + h * 7.0);  // beads form, then dry / blow off
	float a = smoothstep(0.0, 0.08, life) * (1.0 - smoothstep(0.75, 1.0, life));
	vec2 d = (f - c) / vec2(r, r * (1.0 + stretch * 0.9));
	d.y = d.y < 0.0 ? d.y * 0.6 : d.y;  // round head downstream, tapering tail upstream
	float l = length(d);
	float m = (1.0 - smoothstep(0.65, 1.0, l)) * a;
	return vec3(m, d * m);
}

void fragment() {
	if (precip < 0.002) discard;
	vec3 n = normalize(v_n);
	vec3 aft = vec3(1.0, 0.0, 0.0);
	vec3 flow = aft - n * dot(aft, n);
	flow = length(flow) > 0.05 ? normalize(flow) : vec3(0.0, 1.0, 0.0);
	vec3 side = normalize(cross(n, flow));
	vec2 q = vec2(dot(v_pos, side), dot(v_pos, flow));
	float spd = rain_airspeed;
	float move = max(spd - 8.0, 0.0) * 0.045;          // m/s along the glass
	float stretch = clamp(move * 1.2, 0.0, 3.5);
	float blown = 1.0 - 0.6 * smoothstep(15.0, 45.0, spd);  // fewer beads cling at speed
	float dens = clamp(precip * 1.2, 0.0, 1.0);
	vec3 a = drops(q, 0.011, dens * 0.4 * blown, move * 0.5, stretch * 0.5, 1.0);
	vec3 b = drops(q + 0.37, 0.024, dens * 0.22, move, stretch, 7.0);
	vec3 c = drops(q * 1.3 + 0.71, 0.015, dens * 0.3 * smoothstep(5.0, 25.0, spd), move * 1.6, stretch * 1.4, 13.0);
	float m = clamp(a.x + b.x + c.x, 0.0, 1.0);
	vec2 g = a.yz + b.yz + c.yz;
	// perturbed normal (view space) so drops catch the sun and sky
	vec3 side_v = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(side, 0.0))).xyz);
	vec3 flow_v = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(flow, 0.0))).xyz);
	NORMAL = normalize(NORMAL + (side_v * g.x + flow_v * g.y) * 0.9);
	// a drop is a little lens showing the bright sky (upside down): light core, darker rim
	float rim = smoothstep(0.3, 0.95, length(g) / max(m, 1e-3));
	ALBEDO = vec3(0.02);
	EMISSION = fog_color * mix(1.15, 0.55, rim) * m + fog_color * 0.9 * (1.0 - m);
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
	float film = 0.04 + 0.08 * precip;  // the wet sheet on the glass
	ALPHA = clamp(m * 0.55 + film * precip, 0.0, 0.7);
}
