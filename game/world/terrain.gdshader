shader_type spatial;
render_mode fog_disabled;
// Terrain node: displaces the shared TerrainMesh grid from a 16-bit heightmap
// (RG8 = little-endian uint16) and colours it with satellite imagery.
// A node may cover a sub-rectangle of its source tile (virtual levels below L0).

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D img_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform ivec2 texel_off;       // first heightmap texel of this node
uniform int texel_step;        // heightmap texels per grid cell
uniform float tile_size;       // metres covered by this node
uniform vec2 img_off;          // imagery UV of this node's SW corner (v measured from north)
uniform float img_scale;       // imagery UV span of this node
uniform float h_scale = 0.1;
uniform float h_offset = -100.0;
uniform float tile_n = 256.0;
uniform float skirt_depth = 30.0;
global uniform vec3 fog_color;      // set by SkyTime (visibility / time of day)
global uniform float haze_density;
global uniform vec2 world_origin;   // FloatingOrigin (ENU east, north of render 0,0,0)
global uniform vec3 sky_top_color;
uniform sampler2D lc_tex : filter_linear, repeat_disable;  // land class: 255 = water

varying float v_dist;
varying vec2 v_en;  // world east/north (m)

float h_at(ivec2 t) {
	vec2 rg = texelFetch(height_tex, clamp(t, ivec2(0), ivec2(int(tile_n))), 0).rg;
	return (round(rg.r * 255.0) + round(rg.g * 255.0) * 256.0) * h_scale + h_offset;
}

void vertex() {
	ivec2 g = ivec2(round(UV * 64.0));
	ivec2 t = texel_off + g * texel_step;
	float h = h_at(t);
	float sp = tile_size / (64.0 * float(texel_step)); // metres per texel
	float dx = (h_at(t + ivec2(1, 0)) - h_at(t - ivec2(1, 0))) / (2.0 * sp);
	float dn = (h_at(t + ivec2(0, 1)) - h_at(t - ivec2(0, 1))) / (2.0 * sp);
	NORMAL = normalize(vec3(-dx, 1.0, dn));
	VERTEX = vec3(UV.x * tile_size, h - UV2.x * skirt_depth, -UV.y * tile_size);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec3 wr = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_en = vec2(wr.x + world_origin.x, -wr.z + world_origin.y);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// small wind waves: height field gradient from scrolling noise octaves
vec2 wave_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);
	float a = 1.0, f = 0.08;
	for (int i = 0; i < 4; i++) {
		vec2 q = p * f + vec2(t * 0.6, t * 0.35) * f * 3.0;
		float e = 0.05;
		g += a * vec2(vnoise(q + vec2(e, 0)) - vnoise(q - vec2(e, 0)), vnoise(q + vec2(0, e)) - vnoise(q - vec2(0, e))) / (2.0 * e) * f;
		a *= 0.5; f *= 2.1;
	}
	return g;
}

void fragment() {
	vec2 uv = img_off + vec2(UV.x, -UV.y) * img_scale;
	vec3 col = texture(img_tex, uv).rgb;
	// Sentinel-2 mosaics are dark and slightly blue-shifted; lift for daylight.
	col = pow(col, vec3(0.85)) * 1.15;
	float water = smoothstep(0.88, 0.97, texture(lc_tex, uv).r);
	float rough = 0.95;
	float spec = 0.1;
	if (water > 0.0) {
		vec2 g = wave_grad(v_en, TIME) * 1.4 * (1.0 - smoothstep(150.0, 2500.0, v_dist));
		vec3 nw = normalize(vec3(-g.x, 1.0, g.y));  // render frame: x east, y up, z south
		vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
		float fres = pow(1.0 - clamp(dot(nv, VIEW), 0.0, 1.0), 4.0);
		vec3 deep = vec3(0.05, 0.13, 0.15);  // Arabian Sea: grey-green-blue
		vec3 shallow = col * 0.75;  // keep the satellite tint near coasts and creeks
		vec3 sky = mix(sky_top_color, fog_color, 0.35);
		vec3 wcol = mix(mix(deep, shallow, 0.4), sky, clamp(fres * 0.75 + 0.04, 0.0, 0.85));
		col = mix(col, wcol, water);
		NORMAL = normalize(mix(NORMAL, nv, water));
		rough = mix(rough, 0.06, water);
		spec = mix(spec, 0.6, water);
	}
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = mix(col, fog_color, haze * 0.75);
	ROUGHNESS = rough;
	SPECULAR = spec;
}
