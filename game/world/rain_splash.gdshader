shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// Rain splash crowns (world/rain_splash.gd, GPU particles): a camera-facing sprite kept at the particle's scale, tinted by
// the daylight like WeatherFx's rain streaks (so dark at night, never glowing), faded out close to the camera. A splash
// born where the aircraft shelters the ground (under the fuselage or a wing: two boxes in the aircraft's ground frame,
// set by GroundFx) is collapsed in the vertex shader, so it costs no pixels.

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 tint = vec3(0.85, 0.87, 0.9);
uniform vec3 shelter_pos = vec3(0.0, -1e6, 0.0);  // aircraft reference point (render frame)
uniform vec2 shelter_fwd = vec2(0.0, -1.0);      // its nose direction (render x, z)
uniform vec4 shelter_body = vec4(0.0);           // fuselage box: centre along, half length, half width, top height
uniform vec4 shelter_wing = vec4(0.0);           // wing box: centre along, half chord, half span, top height

bool in_box(vec2 p, vec4 b) {
	return abs(p.x - b.x) < b.y && abs(p.y) < b.z;
}

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;  // the particle (local_coords: the emitter transform is in MODEL_MATRIX)
	vec2 d = c.xz - shelter_pos.xz;
	vec2 loc = vec2(dot(d, shelter_fwd), dot(d, vec2(-shelter_fwd.y, shelter_fwd.x)));
	bool low = c.y - shelter_pos.y < max(shelter_body.w, shelter_wing.w);
	if (low && (in_box(loc, shelter_body) || in_box(loc, shelter_wing))) {
		VERTEX = vec3(0.0);  // sheltered: no splash
	}
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 bb = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(sc.x, 0.0, 0.0, 0.0), vec4(0.0, sc.y, 0.0, 0.0), vec4(0.0, 0.0, sc.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = tint * COLOR.rgb;
	ALPHA = t.a * COLOR.a * smoothstep(0.3, 1.5, length(VERTEX));
}
