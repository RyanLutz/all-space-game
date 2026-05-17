shader_type spatial;
render_mode unshaded, depth_draw_never, blend_add;

uniform float point_size : hint_range(0.5, 10.0) = 3.0;

// Distance-based billboard scale (tunable from world_config.json)
uniform float u_dist_ref      : hint_range(50.0,  2000.0) = 500.0;
uniform float u_scale_min     : hint_range(0.1,   2.0)    = 0.5;
uniform float u_scale_max     : hint_range(0.5,   10.0)   = 5.0;
uniform float u_scale_factor  : hint_range(0.1,   5.0)    = 1.0;

// Core + halo glow (tunable from world_config.json)
uniform float u_core_size      : hint_range(0.01, 0.5)  = 0.08;
uniform float u_core_intensity : hint_range(0.1,  2.0)  = 1.0;
uniform float u_halo_strength  : hint_range(0.0,  1.0)  = 0.3;

varying vec4 v_instance_custom;

void vertex() {
	// Billboard: align quad to camera view plane
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	// Distance-based size: maintain consistent screen-space size
	// so stars stay ~5 pixels across at all viewing distances.
	vec3 world_pos = MODEL_MATRIX[3].xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float dist = distance(world_pos, cam_pos);
	float screen_scale = clamp(dist / u_dist_ref * u_scale_factor, u_scale_min, u_scale_max);
	VERTEX.xy *= point_size * screen_scale;
	v_instance_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec4 col = COLOR;
	float lod_alpha = v_instance_custom.r;

	// Centered UV [-0.5, 0.5]
	vec2 uv = UV - 0.5;
	float d = length(uv);

	// Core + halo glow: sharp small core, soft outer glow to billboard edge
	float core = smoothstep(u_core_size, 0.0, d) * u_core_intensity;
	float halo = smoothstep(0.5, 0.0, d) * u_halo_strength;
	float alpha = (core + halo) * lod_alpha;

	// All stars get destination-level brightness
	float brightness = col.a * 1.5;

	ALBEDO = col.rgb * brightness * 2.0;
	ALPHA = alpha;
}
