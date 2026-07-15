shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_disabled;

// Palette textures stay crisp, matching the low-resolution texture authored in Blender.
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0);

// The light-facing side uses the source color; the opposite side uses shadow_tint.
uniform vec4 shadow_tint : source_color = vec4(0.42, 0.50, 0.68, 1.0);
uniform float shadow_threshold : hint_range(-0.5, 0.8, 0.01) = 0.12;
uniform float shadow_softness : hint_range(0.001, 0.25, 0.001) = 0.025;
uniform float ambient_strength : hint_range(0.0, 1.0, 0.01) = 0.18;

void fragment() {
	vec3 base_color = texture(albedo_texture, UV).rgb * albedo_tint.rgb;
	ALBEDO = base_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = base_color * ambient_strength;
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float lit_band = smoothstep(
		shadow_threshold - shadow_softness,
		shadow_threshold + shadow_softness,
		ndotl
	);
	vec3 toon_color = mix(shadow_tint.rgb, vec3(1.0), lit_band);
	DIFFUSE_LIGHT += ALBEDO * toon_color * LIGHT_COLOR * ATTENUATION;
}
