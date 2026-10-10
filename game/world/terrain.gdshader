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
uniform vec3 fog_color : source_color = vec3(0.70, 0.78, 0.88);
uniform float haze_density = 0.000018;

varying float v_dist;

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
}

void fragment() {
	vec2 uv = img_off + vec2(UV.x, -UV.y) * img_scale;
	vec3 col = texture(img_tex, uv).rgb;
	// Sentinel-2 mosaics are dark and slightly blue-shifted; lift for daylight.
	col = pow(col, vec3(0.85)) * 1.15;
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = mix(col, fog_color, haze * 0.75);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
