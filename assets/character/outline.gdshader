shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;
group_uniforms Base;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, hint_default_white, filter_nearest, repeat_disable;
uniform float ambient_strength : hint_range(0.0, 1.0, 0.01) = 0.15;

group_uniforms ToonLighting;
// Diffuse curve. This is, in my opinion, what defines a toon shader. A
// photo-realistic shader should have a linear curve starting at 0 and
// finishing at 1, and a toon shader should start at 0 and get to 1 almost
// instantaneously. The length of this transition is its smoothing, working
// the same way as the specular and rim light smoothing uniforms. Another
// common curve is to make it a staircase, which would result in multiple
// shading bands. Check the video for a more detailed explanation.
uniform sampler2D diffuse_curve : hint_default_white, filter_linear, repeat_disable;
uniform vec4 shadow_tint : source_color = vec4(0.42, 0.50, 0.68, 1.0);
uniform float shadow_threshold : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float shadow_softness : hint_range(0.001, 0.5, 0.001) = 0.05;

group_uniforms Specular;
// Specular light uniforms. Set specular to zero to turn off the effect.
// The texture map uses the red channel for the specular value, green for amount
// and blue for smoothness.
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float specular_amount : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float specular_smoothness : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform sampler2D texture_specular : hint_default_white;

group_uniforms RimLight;
// Rim light uniforms. Set rim to zero to turn off the effect.
// The texture map uses the red channel for the rim value, green for rim amount
// and blue for smoothness.
uniform float rim : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float rim_amount : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float rim_smoothness : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform sampler2D texture_rim : hint_default_white;

group_uniforms Surface;
// Roughness and metallic here are only for reflection purposes if you are
// using SS reflections or want the sky reflected on your material. In most
// cases you don't want to change those, but you can try them. The surface
// texture maps the red channel to roughness and the green channel to metallic.
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform sampler2D texture_surface : hint_default_white;

group_uniforms Emission;
// Emission from base code.
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0, 0.05) = 1.0;
uniform sampler2D texture_emission : source_color, hint_default_black;

group_uniforms NormalMapping;
// Normal map from base code.
uniform float normal_scale : hint_range(-2.0, 2.0, 0.01) = 1.0;
uniform sampler2D texture_normal : hint_normal;

group_uniforms Parallax;
// Depth map from base code.
uniform float depth_scale : hint_range(0.0, 0.05, 0.001) = 0.0;
uniform int depth_min_layers : hint_range(1, 16, 1) = 8;
uniform int depth_max_layers : hint_range(1, 32, 1) = 24;
uniform bool flip_tangent = false;
uniform bool flip_binormal = false;
// White represents zero depth after the inversion in fragment(), so an
// unassigned texture remains flat and performs no extra sampling.
uniform sampler2D texture_depth : hint_default_white, filter_linear_mipmap;

group_uniforms AmbientOcclusion;
// Ambient occlusion from base code.
uniform float ao_light_affect : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform sampler2D ao_map : hint_default_white;

group_uniforms Anisotropy;
// Anisotropy from base code.
uniform float anisotropy_ratio : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform vec3 anisotropy_direction = vec3(0.0, -1.0, 0.0);
uniform float aniso_map_dir_ratio : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform sampler2D anisotropy_flowmap : hint_anisotropy;

group_uniforms SubsurfaceScattering;
// Subsurface scattering, from base code.
uniform float subsurface_scattering : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform sampler2D texture_sss : hint_default_white;

group_uniforms Transmission;
// Transmission, from base code.
uniform vec4 transmission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D texture_transmission : source_color, hint_default_black;

group_uniforms Refraction;
// Refraction from base code.
uniform float refraction : hint_range(-0.1, 0.1, 0.001) = 0.0;
const vec4 refraction_texture_channel = vec4(1.0, 0.0, 0.0, 0.0); // Refraction channel is set to red.
uniform sampler2D texture_refraction;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

group_uniforms UVTransform;
// UV scale and offset from base code.
uniform vec2 uv_scale = vec2(1,1);
uniform vec2 uv_offset = vec2(0,0);
group_uniforms;



// Vertex function to deal with UV scale and offset, straight out of base code.
void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
}



void fragment() {
	vec2 base_uv = UV;

	// Depth from base code, with deep parallax enabled. Slightly modified so that
	// black are deeps and white are peaks, as well as turning depth flip into bools.
	// The bounded loop is intentional: data-dependent while loops can hang the
	// OpenGL Compatibility renderer while this value is adjusted in the editor.
	if (depth_scale != 0.0) {
		vec2 depth_flip = vec2(flip_tangent ? -1.0 : 1.0, flip_binormal ? -1.0 : 1.0);
		vec3 view_dir = normalize(normalize(-VERTEX)*mat3(TANGENT*depth_flip.x,-BINORMAL*depth_flip.y,NORMAL));
		int minimum_layers = min(depth_min_layers, depth_max_layers);
		int maximum_layers = max(depth_min_layers, depth_max_layers);
		int layer_count = int(mix(float(maximum_layers), float(minimum_layers), abs(view_dir.z)));
		layer_count = clamp(layer_count, 1, 32);
		float layer_depth = 1.0 / float(layer_count);
		vec2 P = view_dir.xy * depth_scale;
		vec2 delta = P / float(layer_count);
		vec2 ofs = base_uv;
		float depth = 1.0 - textureLod(texture_depth, ofs, 0.0).r;
		float current_depth = 0.0;
		for (int layer = 0; layer < 32; layer++) {
			if (layer >= layer_count || current_depth >= depth) {
				break;
			}
			ofs -= delta;
			depth = 1.0 - textureLod(texture_depth, ofs, 0.0).r;
			current_depth += layer_depth;
		}
		vec2 prev_ofs = ofs + delta;
		float after_depth  = depth - current_depth;
		float before_depth = 1.0 - textureLod(texture_depth, prev_ofs, 0.0).r - current_depth + layer_depth;
		float denominator = after_depth - before_depth;
		float weight = abs(denominator) > 0.00001 ? clamp(after_depth / denominator, 0.0, 1.0) : 0.0;
		base_uv = mix(ofs, prev_ofs, weight);
	}
	vec4 base_color = albedo * texture(texture_albedo, base_uv);

	ROUGHNESS = roughness * texture(texture_surface, base_uv).r;
	METALLIC = metallic * texture(texture_surface, base_uv).g;

	// Normal map, straight out of base code.
	NORMAL_MAP = texture(texture_normal, base_uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;

	// Ambient occlusion, straight out of base code on the red channel.
	AO = texture(ao_map, base_uv).r;
	AO_LIGHT_AFFECT = ao_light_affect;

	// Emission, straight out of base code with additive mode.
	EMISSION = (emission.rgb + texture(texture_emission, base_uv).rgb) * emission_energy;
	EMISSION += base_color.rgb * ambient_strength;

	// Subsurface scattering, straight out of base code. I put it on the transparency
	// shader because it is a transparency effect, but it actually doesn't work if the
	// object is on the transparent pipeline. If you want to use that effect, comment
	// out the refraction code and leave the alpha value commented out as well.
	SSS_STRENGTH = subsurface_scattering * texture(texture_sss, base_uv).r;

	// Transmission, straight out of base code. It works best when on the
	// transparent pipeline or with shadows disabled, just make sure it is
	// not showing its own shadow on its back.
	BACKLIGHT = transmission.rgb + texture(texture_transmission, base_uv).rgb;

	// Refraction, slightly modified. It doesn't actually uses the alpha value, instead
	// it reads from the screen texture in order to distort the image to make refraction.
	// This means nothing else that reads from it will appear through it, and things on the
	// alpha channel also have troubles showing behind them. If you want to disable refraction
	// and just use the alpha channel, just take out all of the following uncommented lines
	// and uncomment the commented ones.
	vec3 normal = normalize(mix(NORMAL,TANGENT*NORMAL_MAP.x + BINORMAL*NORMAL_MAP.y + NORMAL*NORMAL_MAP.z,NORMAL_MAP_DEPTH));
	vec2 ref_ofs = SCREEN_UV - normal.xy * dot(texture(texture_refraction, base_uv), refraction_texture_channel) * refraction;
	float ref_amount = 1.0 - base_color.a;
	EMISSION += textureLod(screen_texture, ref_ofs, 0.0).rgb * ref_amount;
	ALBEDO = (1.0 - ref_amount) * base_color.rgb;
	ALPHA = 1.0;
//	ALBEDO = albedo.rgb * texture(texture_albedo, UV).rgb;
//	ALPHA = albedo.a * texture(texture_albedo, UV).a;
}



void light() {
	// Let's start by incorporating specular and rim textures. Pay attention to
	// the channels and what each value does.
	float spec_value = specular * texture(texture_specular, UV).r;
	float spec_gloss = pow(2.0, 8.0 * (1.0 - specular_amount * texture(texture_specular, UV).g));
	float spec_smooth = specular_smoothness * texture(texture_specular, UV).b;
	float rim_value = rim * texture(texture_rim, UV).r;
	float rim_width = rim_amount * texture(texture_rim, UV).g;
	float rim_smooth = rim_smoothness * texture(texture_rim, UV).b;

	// Diffuse part. We take the dot product between light and normal, multiply it by attenuation
	// and apply it to the diffuse curve. This means the diffuse curve gets to do the dot product
	// smoothing, set multiple light bands each with its own tone and smoothing, etc etc. I reccomend
	// using the gradient tool to make a curve, since it gives you control of each point's position
	// and color with precision. The curve tool works too, it gives you control of different
	// interpolation methods but you have less control over each point's exact position and value.
	float diffuse_value = smoothstep(
		shadow_threshold - shadow_softness,
		shadow_threshold + shadow_softness,
		dot(LIGHT, NORMAL)
	);
	float diffuse_band = texture(diffuse_curve, vec2(diffuse_value, 0.5)).r;
	float litness = diffuse_band * ATTENUATION;
	vec3 toon_tint = mix(shadow_tint.rgb, vec3(1.0), diffuse_band);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * (toon_tint * ATTENUATION + BACKLIGHT * (ATTENUATION - litness));

	// Specular part. We use the Blinn-Phong specular calculations with a smoothstep
	// function to toonify. Mess with the specular uniforms to see what each one does.
	// It also deals with anisotropy. If you want to remove anisotropy calculations,
	// remove flowchart, aniso_dir, aniso and replace spec by dot(NORMAL, half).
	vec3 half = normalize(VIEW + LIGHT);
	vec3 flowchart = (texture(anisotropy_flowmap, UV).rgb * 2.0 - 1.0);
	vec3 aniso_dir = mix(normalize(anisotropy_direction), flowchart, aniso_map_dir_ratio);
	float aniso = max(0, sin(dot(normalize(NORMAL + aniso_dir), half) * PI));
	float spec = max(mix(dot(NORMAL, half), aniso, anisotropy_ratio * texture(anisotropy_flowmap, UV).a), 0.0);
	float spec_intensity = pow(spec, spec_gloss * spec_gloss);
	spec_intensity = smoothstep(0.05, 0.05 + spec_smooth, spec_intensity);
	SPECULAR_LIGHT += LIGHT_COLOR * spec_value * spec_intensity * litness;

	// Rim part. We use the view and normal vectors only to find out if we're looking
	// at a pixel from the edge of the object or not. We add the final value to specular
	// light values so that Godot treats it as specular.
	float rim_dot = 1.0 - dot(NORMAL, VIEW);
	float rim_threshold = pow((1.0 - rim_width), dot(LIGHT, NORMAL));
	float rim_intensity = smoothstep(rim_threshold - rim_smooth/2.0, rim_threshold + rim_smooth/2.0, rim_dot);
	SPECULAR_LIGHT += LIGHT_COLOR * rim_value * rim_intensity * litness;
}
