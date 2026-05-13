shader_type spatial;
render_mode unshaded, depth_draw_never;

uniform float point_size : hint_range(0.5, 10.0) = 3.0;

varying vec4 v_instance_custom;

void vertex() {
	// Billboard: align quad to camera view plane
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	VERTEX.xy *= point_size;
	v_instance_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec4 col = COLOR;
	float lod_alpha = v_instance_custom.r;
	float is_dest = v_instance_custom.g;

	// Centered UV [-0.5, 0.5]
	vec2 uv = UV - 0.5;
	float d = length(uv);

	// Soft disc glow
	float alpha = smoothstep(0.5, 0.0, d) * lod_alpha;

	// Destination stars are brighter
	float brightness = col.a * (1.0 + is_dest * 0.5);

	ALBEDO = col.rgb * brightness * alpha * 2.0;
}
