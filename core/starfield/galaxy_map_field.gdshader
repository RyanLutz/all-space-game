shader_type spatial;
render_mode unshaded, depth_draw_never, cull_front, blend_add;

uniform float galaxy_scale : hint_range(1.0, 1000.0) = 100.0;
uniform float proc_field_cell_size : hint_range(100.0, 5000.0) = 800.0;
uniform float proc_star_density : hint_range(0.9, 1.0) = 0.997;
uniform float proc_core_boost : hint_range(0.5, 5.0) = 2.0;
uniform float proc_disc_falloff : hint_range(0.0, 2.0) = 0.4;

// ────────────────────────────────────────────────────────────────────────────
//  Value noise — 3D hash-based (copied from galaxy_sky.gdshader)
// ────────────────────────────────────────────────────────────────────────────

float hash(vec3 p) {
	p = fract(p * vec3(443.8975, 397.2973, 491.1871));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(
			mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x),
			f.y),
		mix(
			mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x),
			f.y),
		f.z);
}

// ────────────────────────────────────────────────────────────────────────────
//  Fragment
// ────────────────────────────────────────────────────────────────────────────

void fragment() {
	// World position of this fragment
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Camera position in world space (same as GalaxyContainer center)
	vec3 cam_world_pos = INV_VIEW_MATRIX[3].xyz;

	// Distance from camera in scaled space
	float cam_dist = length(world_pos - cam_world_pos);

	// Convert world position back to galaxy coordinates
	vec3 galaxy_pos = world_pos * galaxy_scale;

	// Galaxy structure: same density model as sky shader
	float gal_radius = length(galaxy_pos.xz) / 100000.0;
	float core_factor = mix(proc_core_boost, 1.0, clamp(gal_radius, 0.0, 1.0));
	float disc_y = abs(galaxy_pos.y) / 8000.0;
	float disc_factor = 1.0 - clamp(disc_y * proc_disc_falloff, 0.0, 0.85);
	float arm_noise = vnoise(normalize(galaxy_pos) * 3.0);
	float arm_factor = mix(0.85, 1.0, arm_noise);

	// Hash 3D cell for star presence
	vec3 cell_id = floor(galaxy_pos / proc_field_cell_size);
	float cell_hash = hash(cell_id * 7.3 + vec3(13.7, 5.1, 9.3));

	float star_prob = (1.0 - proc_star_density) * core_factor * disc_factor * arm_factor;
	star_prob = clamp(star_prob, 0.0, 1.0);

	vec3 color = vec3(0.0);
	float alpha = 0.0;
	if (cell_hash < star_prob) {
		float color_h = hash(cell_id * 3.1 + vec3(7.0, 2.0, 5.0));
		vec3 star_color = mix(vec3(1.0, 0.85, 0.7), vec3(0.8, 0.9, 1.0), color_h);
		float brightness_h = hash(cell_id * 5.7 + vec3(1.0, 9.0, 3.0));
		float star_bright = mix(0.3, 1.0, brightness_h) * 0.8;
		color = star_color * star_bright;
		alpha = star_bright * 0.5;
	}

	ALBEDO = color;
	ALPHA = alpha;
}
