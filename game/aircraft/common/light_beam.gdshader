shader_type spatial;
// Faint visible beam of the landing / taxi light (a cone mesh along the spot's -Z):
// bright at the lamp, fading along the beam and toward the cone's silhouette edges.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.95, 0.85);
uniform float intensity = 0.0;
uniform float length_m = 30.0;

varying float v_t;

void vertex() {
	v_t = clamp(VERTEX.y / length_m + 0.5, 0.0, 1.0);  // 0 at the lamp, 1 at the far end
}

void fragment() {
	float along = pow(1.0 - v_t, 2.2);
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = color * intensity * along * face * face;
}
