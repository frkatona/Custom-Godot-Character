shader_type spatial;
render_mode specular_disabled;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = abs(fract(world_position.xz / 2.0 - 0.5) - 0.5);
	vec2 width = max(fwidth(world_position.xz / 2.0), vec2(0.0001));
	float line = 1.0 - min(min(cell.x / width.x, cell.y / width.y), 1.0);
	ALBEDO = mix(vec3(0.20, 0.27, 0.29), vec3(0.31, 0.40, 0.41), line * 0.65);
	ROUGHNESS = 1.0;
}
