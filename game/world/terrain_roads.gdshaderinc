// Road / river ribbons for terrain.gdshader (tools/20_roads_rivers.py -> terrain/ro/0/<tx>_<ty>.png).
// ro_tex is a 4 m texel signed-distance field, filtered bilinearly: L = e (metres from the ribbon edge,
// e = byte * 0.16 - 6, negative inside, saturated at +4), A = class (kind + 1: 1 motorway, 2 trunk, 3 primary, 4 secondary,
// 5 tertiary, 6 unclassified, 7 residential, 8 service, 9 track, 10 river, 11 canal, 12 stream, 13 drain),
// read without filtering. Only nodes within ~3.6 km bind a tile (TerrainRoads), everything fades by ~3.3 km.

uniform sampler2D ro_tex : filter_linear, repeat_disable;
uniform vec3 ro_rect = vec3(0.0, 1.0, 1.0);  // uv of the node's SW corner (v from north), uv span
uniform float ro_on = 0.0;

// drawn half-width per class (m), must match road_raster.KIND_HW floored at HW_MIN
const float RO_HW[14] = float[14](2.2, 5.5, 5.0, 4.5, 3.8, 3.2, 2.8, 2.5, 2.2, 2.2, 6.0, 4.0, 2.2, 2.2);

// e (m from the ribbon edge) and class at this fragment; class 0 = none
void ro_fetch(vec2 uv, out float e, out int cls) {
	ivec2 sz = textureSize(ro_tex, 0);
	e = texture(ro_tex, uv).r * 40.8 - 6.0;  // 255 * 0.16
	cls = int(texelFetch(ro_tex, clamp(ivec2(uv * vec2(sz)), ivec2(0), sz - 1), 0).a * 255.0 + 0.5);
}

// asphalt / dirt surface colour (linear) with edge lines and a centre line on the bigger roads.
// dc: metres from the centreline, aa: pixel footprint (m), dist: camera distance
vec3 road_surface(int cls, float dc, float aa, float dist, vec2 en) {
	float wear = vnoise(en * 0.11) * 0.6 + vnoise(en * 1.3) * 0.4;
	if (cls == 9) {  // track: packed earth with two darker wheel ruts
		float rut = 1.0 - smoothstep(0.1, 0.45, abs(abs(dc) - 0.75));
		return vec3(0.27, 0.19, 0.11) * (0.8 + 0.4 * wear) * (1.0 - 0.18 * rut * (1.0 - smoothstep(60.0, 300.0, dist)));
	}
	float minor = step(5.5, float(cls));
	vec3 asphalt = mix(vec3(0.062, 0.062, 0.066), vec3(0.115, 0.11, 0.105), wear * (0.5 + 0.6 * minor));
	if (cls == 8) { asphalt = mix(asphalt, vec3(0.14, 0.12, 0.09), 0.35); }  // service roads: patchy
	// polished tyre tracks: slightly darker bands at a third of the half-width
	float hw = RO_HW[cls];
	asphalt *= 1.0 - 0.12 * (1.0 - smoothstep(0.15, 0.7, abs(abs(dc) - hw * 0.4))) * (1.0 - smoothstep(80.0, 500.0, dist)) * (1.0 - minor);
	float mk_k = (1.0 - smoothstep(90.0, 650.0, dist)) * step(float(cls), 5.5);
	if (mk_k > 0.0) {
		float w = max(0.07, aa * 0.8);
		float edge = 1.0 - smoothstep(w, w + aa, abs(abs(dc) - (hw - 0.4)));
		float centre = (1.0 - smoothstep(w, w + aa, abs(dc))) * step(2.5, float(cls)) * step(float(cls), 5.5);
		float lane = (1.0 - smoothstep(w, w + aa, abs(abs(dc) - hw * 0.5))) * step(float(cls), 2.5) * 0.5;
		vec3 paint = mix(vec3(0.62, 0.62, 0.6), vec3(0.58, 0.46, 0.1), step(0.5, centre));
		asphalt = mix(asphalt, paint, clamp(edge + centre + lane, 0.0, 1.0) * mk_k * (0.75 + 0.25 * wear));
	}
	return asphalt;
}
