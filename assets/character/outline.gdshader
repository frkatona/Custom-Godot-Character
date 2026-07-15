shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.035, 0.025, 0.045, 1.0);
uniform float outline_width : hint_range(0.0, 12.0, 0.1) = 3.0;

void vertex() {
	// Expand back faces in clip space so the outline stays the same width on screen.
	vec4 clip_position = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 clip_normal = mat3(PROJECTION_MATRIX * MODELVIEW_MATRIX) * NORMAL;
	vec2 direction = normalize(clip_normal.xy + vec2(0.00001));
	clip_position.xy += direction * (outline_width * 2.0 / VIEWPORT_SIZE) * clip_position.w;
	POSITION = clip_position;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
