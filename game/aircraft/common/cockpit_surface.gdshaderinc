// Cockpit surfaces (aircraft/common/cockpit_surface.gd converts the cockpit's StandardMaterial3D surfaces to these).
// Same look as the StandardMaterial3D features the cockpit glbs use (albedo, roughness, metallic, specular, AO,
// additive emission, alpha), plus:
// 1. Camera-relative position in the cockpit view (cockpit_precise.gdshaderinc), so the cockpit stays rigid at altitude.
// 2. Anisotropic filtering, so placards stay readable at grazing angles (the overhead seen from the seat).
// 3. Display quads (unshaded) average four taps across the pixel: their SubViewport has no mipmaps.
// Variant switches, #defined before the #include: CKPT_LIT (else unshaded), CKPT_ALPHA.

#include "res://aircraft/common/cockpit_precise.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
#ifdef CKPT_LIT
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 metallic_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D texture_ambient_occlusion : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 ao_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float ao_light_affect : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D texture_emission : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float emission_energy = 0.0;
#endif

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	CKPT_PRECISE_MODELVIEW
}

void fragment() {
#ifdef CKPT_LIT
	vec4 albedo_tex = texture(texture_albedo, UV);
#else
	// Display quads show a SubViewport, which has no mipmaps: from the seat its text is 2-3 texels a pixel and
	// shimmered. Four taps across this pixel's footprint; zoomed in (footprint under a texel) it is one plain sample.
	vec2 qx = dFdx(UV) * 0.25;
	vec2 qy = dFdy(UV) * 0.25;
	vec4 albedo_tex = 0.25 * (texture(texture_albedo, UV + qx + qy) + texture(texture_albedo, UV - qx - qy)
			+ texture(texture_albedo, UV + qx - qy) + texture(texture_albedo, UV - qx + qy));
#endif
	ALBEDO = albedo.rgb * albedo_tex.rgb;
#ifdef CKPT_ALPHA
	ALPHA = albedo.a * albedo_tex.a;
#endif
#ifdef CKPT_LIT
	METALLIC = metallic * dot(texture(texture_metallic, UV), metallic_texture_channel);
	ROUGHNESS = roughness * dot(texture(texture_roughness, UV), roughness_texture_channel);
	SPECULAR = specular;
	AO = dot(texture(texture_ambient_occlusion, UV), ao_texture_channel);
	AO_LIGHT_AFFECT = ao_light_affect;
	EMISSION = (emission.rgb + texture(texture_emission, UV).rgb) * emission_energy;
#endif
}
