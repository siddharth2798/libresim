shader_type spatial;
// Puts Godot's volumetric (froxel) fog back onto the fog_disabled materials (terrain, buildings, trees, water, the
// sky), which draw their own haze and skip the engine's fog. One mesh of n + 1 full-screen planes at fixed view
// depths (VfogRules.slice_depth, spaced like the froxel slices), drawn first among the transparents. A pixel whose
// scene depth lies between planes i and i + 1 is written by plane i (alpha 1) and plane i + 1 (alpha = the fraction),
// so the engine's fog, sampled at each plane's own depth, is interpolated linearly in between.
// Each plane outputs the opaque image A with the engine's fog applied: Godot also adds its Environment fog here
// (it cannot be switched off per material), so the albedo is pre-inverted to (A - F f) / (1 - f), which the
// engine's mix(albedo, F, f) turns back into A; only the volumetric part remains:  A (1 - v.a) + v.rgb v.a.
// Valid for exponential Environment fog without aerial perspective / sun scatter / height fog (VolumetricFog checks).
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, blend_mix, skip_vertex_transform;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float z0 = 20.0;  // m, first plane; nearer pixels (the aircraft, the cockpit) keep their own fog
uniform float z1 = 5000.0;  // m, last plane (froxel length or where the Environment fog is nearly opaque)
uniform float n = 16.0;  // planes 0..n
uniform float spread = 2.0;  // VfogRules.SPREAD
uniform float env_k = 0.0;  // Environment fog density (1/m), 0 when it is off
uniform vec3 env_col = vec3(0.0);  // Environment fog colour, linear x energy (sent as a Vector3: a Color would be linearised again)

varying float v_i;

float depth_of(float i) { return z0 + (z1 - z0) * pow(clamp(i / n, 0.0, 1.0), spread); }
float index_of(float z) { return n * pow(clamp((z - z0) / max(z1 - z0, 1e-3), 0.0, 1.0), 1.0 / spread); }

void vertex() {
	v_i = VERTEX.z;  // the mesh stores the plane index in z, the screen corner in xy
	vec4 r = INV_PROJECTION_MATRIX * vec4(VERTEX.xy, 0.5, 1.0);
	vec3 dir = r.xyz / r.w;
	VERTEX = dir * (depth_of(v_i) / -dir.z);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	float zs = 1e9;  // reversed Z: 0 is the sky
	if (d > 0.0) {
		vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
		zs = -v.z / v.w;
	}
	if (zs < z0) {
		discard;
	}
	float s = index_of(zs);
	float a;
	if (s >= v_i && (s < v_i + 1.0 || v_i >= n - 0.5)) {
		a = 1.0;
	} else if (s >= v_i - 1.0 && s < v_i) {
		a = s - (v_i - 1.0);
	} else {
		discard;
	}
	float f = 1.0 - exp(-length(VERTEX) * env_k);
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	ALBEDO = (col - env_col * f) / max(1.0 - f, 1e-3);
	ALPHA = a;
}
