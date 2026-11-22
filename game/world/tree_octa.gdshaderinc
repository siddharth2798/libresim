#ifndef TREE_OCTA_INC
#define TREE_OCTA_INC
// Hemi-octahedral impostor frames: twin of world/tree_octa.gd (same N, encode, frame directions, triangle selection
// and image axes; tests/test_tree_look.gd checks the GDScript side). Directions are in the tree's canonical frame.

const float OCTA_N = 8.0;  // TreeOcta.N

vec2 octa_encode(vec3 d) {
	vec3 v = vec3(d.x, max(d.y, 0.0), d.z);
	vec2 p = vec2(v.x, v.z) / max(abs(v.x) + v.y + abs(v.z), 1e-6);
	return vec2(p.x + p.y, p.x - p.y);
}

vec3 octa_decode(vec2 e) {
	vec2 p = vec2(e.x + e.y, e.x - e.y) * 0.5;
	return normalize(vec3(p.x, 1.0 - abs(p.x) - abs(p.y), p.y));
}

vec3 octa_frame_dir(vec2 ij) {
	return octa_decode(ij / (OCTA_N - 1.0) * 2.0 - 1.0);
}

// Three frames around d (xy = frame, z = weight), as TreeOcta.select (unsorted).
void octa_select(vec3 d, out vec3 f0, out vec3 f1, out vec3 f2) {
	vec2 g = (octa_encode(d) * 0.5 + 0.5) * (OCTA_N - 1.0);
	vec2 c = clamp(floor(g), vec2(0.0), vec2(OCTA_N - 2.0));
	vec2 f = g - c;
	if (f.x + f.y < 1.0) {
		f0 = vec3(c, 1.0 - f.x - f.y);
		f1 = vec3(c + vec2(1.0, 0.0), f.x);
		f2 = vec3(c + vec2(0.0, 1.0), f.y);
	} else {
		f0 = vec3(c + vec2(1.0), f.x + f.y - 1.0);
		f1 = vec3(c + vec2(1.0, 0.0), 1.0 - f.y);
		f2 = vec3(c + vec2(0.0, 1.0), 1.0 - f.x);
	}
}

// Image axes of the view from d (TreeOcta.basis): right, up.
void octa_basis(vec3 d, out vec3 right, out vec3 up) {
	float y = max(d.y, -0.999);
	float k = 1.0 / (1.0 + y);
	right = vec3(1.0 - d.x * d.x * k, -d.x, -d.x * d.z * k);
	up = vec3(d.x * d.z * k, d.z, d.z * d.z * k - 1.0);
}

// Frame-local UV (0..1, v down) of canonical point p (relative to the crown centre) seen along view direction d,
// projected onto frame f's image plane; r = crown radius.
vec2 octa_frame_uv(vec3 rel, vec3 d, vec2 frame, float r) {
	vec3 fd = octa_frame_dir(frame);
	vec3 fr, fu;
	octa_basis(fd, fr, fu);
	vec3 q = rel - d * (dot(rel, fd) / max(dot(d, fd), 0.2));
	return vec2(dot(q, fr), -dot(q, fu)) / (2.0 * r) + 0.5;
}
#endif
