shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Next pass on the fuselage paint only (material_finish.gd). Multiplies nothing and does not
// sample the livery: a transparent brown/grey decal over the StandardMaterial3D, so the albedo
// swap in PaintPipeline stays the paint. Stains are in the aircraft's structural frame
// (x aft, y right, z up). amount 0 (the menu preview, and a flight that has not started) draws nothing.
uniform mat4 aircraft_inv = mat4(1.0);
uniform vec3 cg = vec3(0.0);
uniform float amount = 0.0;
uniform float nozzle_count = 0.0;
uniform vec3 nozzle0 = vec3(0.0);
uniform vec3 nozzle1 = vec3(0.0);
uniform vec3 nozzle2 = vec3(0.0);
uniform vec3 nozzle3 = vec3(0.0);
uniform vec3 dir0 = vec3(1.0, 0.0, 0.0);
uniform vec3 dir1 = vec3(1.0, 0.0, 0.0);
uniform vec3 dir2 = vec3(1.0, 0.0, 0.0);
uniform vec3 dir3 = vec3(1.0, 0.0, 0.0);

varying vec3 ap;
varying vec3 an;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	ap = (aircraft_inv * world).xyz;
	an = mat3(aircraft_inv) * (mat3(MODEL_MATRIX) * NORMAL);
}

// Soft soot along the plume, structural metres. Light: most of the lobe is a few percent of alpha.
float plume(vec3 p, vec3 nozzle, vec3 dir) {
	vec3 d = normalize(dir);
	float along = dot(p - nozzle, d);
	float t = clamp(along, 0.4, 7.0);
	float r = length(p - (nozzle + d * t));
	float body = exp(-r * r / (2.4 * 2.4));
	float fade = smoothstep(0.0, 1.2, along) * smoothstep(8.0, 3.5, along);
	return body * fade;
}

void fragment() {
	// No return: Godot rejects it in fragment(). amount 0 stays clear.
	float dirt = 0.0;
	float soot = 0.0;
	if (amount > 0.001) {
		float nl = length(an);
		if (nl > 0.001) {
			// Nose is -Z in aircraft local space. Only the most forward-facing normals pick up the dirt line.
			float face = clamp(dot(an / nl, vec3(0.0, 0.0, -1.0)), 0.0, 1.0);
			dirt = smoothstep(0.60, 0.90, face);
		}
		vec3 st = vec3(ap.z + cg.x, ap.x + cg.y, ap.y + cg.z);
		if (nozzle_count >= 1.0) soot = max(soot, plume(st, nozzle0, dir0));
		if (nozzle_count >= 2.0) soot = max(soot, plume(st, nozzle1, dir1));
		if (nozzle_count >= 3.0) soot = max(soot, plume(st, nozzle2, dir2));
		if (nozzle_count >= 4.0) soot = max(soot, plume(st, nozzle3, dir3));
	}
	float a = clamp(dirt * 0.16 + soot * 0.28, 0.0, 0.32) * amount;
	ALBEDO = mix(vec3(0.36, 0.34, 0.32), vec3(0.18, 0.15, 0.12), clamp(soot, 0.0, 1.0));
	ALPHA = a;
}
