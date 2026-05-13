shader_type sky;
render_mode use_debanding;

// ─── Star catalog textures ───────────────────────────────────────────────────
// Packed by StarField.rebuild_skybox() once per warp.
// Each texel corresponds to one star (backdrop or destination).
//
// star_directions: RGBAF — (dir.x, dir.y, dir.z, apparent_size)
//   apparent_size is now pixel radius (repurposed from angular threshold).
// star_colors:     RGBA8  — (r, g, b, brightness)
//   brightness is the luminosity weight; blue giants > 1.0, red dwarfs < 0.5.
uniform sampler2D star_directions : filter_nearest, repeat_disable;
uniform sampler2D star_colors     : filter_nearest, repeat_disable;
uniform int star_count = 0;
uniform int tex_width  = 64;
uniform int tex_height = 64;
uniform vec2 viewport_size = vec2(1920.0, 1080.0);

// ─── Nebula volumes ──────────────────────────────────────────────────────────
// Uniform arrays — small count (< 32), packed by StarField._upload_nebula_uniforms().
// nebula_dirs:          normalized direction from player to nebula center (world space)
// nebula_colors:        rgb = nebula color, a = opacity weight
// nebula_angular_radii: angular radius — vol.radius / dist_to_center (chord approx ≈ radians)
uniform int nebula_count = 0;
uniform vec3 nebula_dirs[32];
uniform vec4 nebula_colors[32];
uniform float nebula_angular_radii[32];

// ─── Galaxy-space noise control ──────────────────────────────────────────────
// player_galaxy_position is set once per warp so the noise field shifts
// relative to the player's position in the galaxy — short jumps shift the sky
// slightly, long jumps produce a substantially different nebula pattern.
uniform vec3 player_galaxy_position = vec3(0.0);
uniform float galaxy_noise_influence = 0.00002;
uniform float coarse_frequency = 1.2;
uniform float fine_frequency   = 4.5;
uniform float noise_warp_strength = 0.6;
uniform float nebula_base_opacity = 0.35;

// ─── Galactic map zoom ───────────────────────────────────────────────────────
// 0.0 = full galaxy view (nebula suppressed for clean silhouette read)
// 1.0 = close zoom (full nebula color and cloud detail visible)
// In normal gameplay, leave at 0.0.
uniform float map_zoom = 0.0;

// ─── Procedural hash star field ──────────────────────────────────────────────
uniform float proc_star_density    = 0.997;
uniform float proc_star_brightness = 0.8;
uniform float proc_core_boost      = 2.0;
uniform float proc_disc_falloff    = 0.4;

// ────────────────────────────────────────────────────────────────────────────
//  Value noise — 3D hash-based
// ────────────────────────────────────────────────────────────────────────────

float hash(vec3 p) {
	p = fract(p * vec3(443.8975, 397.2973, 491.1871));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	// Smooth interpolation (C2 continuity)
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(
			mix(hash(i),               hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x),
			f.y),
		mix(
			mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x),
			f.y),
		f.z);
}

// ────────────────────────────────────────────────────────────────────────────
//  Texture UV helper — maps 1D star index to normalized texture UV
// ────────────────────────────────────────────────────────────────────────────

vec2 texel_uv(int idx) {
	int x = idx % tex_width;
	int y = idx / tex_width;
	// +0.5 samples the texel center, avoiding bilinear bleed between stars
	return (vec2(float(x), float(y)) + 0.5) / vec2(float(tex_width), float(tex_height));
}

// ────────────────────────────────────────────────────────────────────────────
//  Sky entry point
// ────────────────────────────────────────────────────────────────────────────

void sky() {
	vec3 rgb = vec3(0.0);

	// ── Nebula / cloud background (rendered first, behind stars) ────────────
	//
	// Key insight: noise is sampled along EYEDIR shifted by player_galaxy_position
	// in galaxy space. This means the noise field exists in galaxy space, not
	// view space — jumping to a different system shifts the player through the
	// noise field rather than rotating it, producing plausible sky continuity
	// across warps.
	vec3 sample_dir = EYEDIR + player_galaxy_position * galaxy_noise_influence;

	// Domain warp: displace the sample direction before evaluating noise.
	// This produces organic cloud shapes (large voids, looping arms) rather
	// than regular noise patterns.
	vec3 warp_offset = vec3(
		vnoise(sample_dir * coarse_frequency),
		vnoise(sample_dir * coarse_frequency + vec3(5.2,  1.3, 2.8)),
		vnoise(sample_dir * coarse_frequency + vec3(9.1,  4.7, 6.3))
	);
	vec3 warped = sample_dir + noise_warp_strength * warp_offset;

	// Two-layer cloud density: coarse gives large void / mass boundaries,
	// fine gives internal wisps and filaments.
	float cloud_density = vnoise(warped * coarse_frequency);
	float cloud_detail  = vnoise(warped * fine_frequency) * 0.4;
	float cloud = clamp(cloud_density + cloud_detail, 0.0, 1.0);

	// Nebula volume tinting — each volume contributes its color weighted by
	// proximity. The angular proximity is computed via chord distance between
	// EYEDIR and the volume's direction, divided by the angular radius.
	// Dark voids emerge naturally from low cloud_density — no special handling.
	vec3  nebula_color  = vec3(0.0);
	float nebula_weight = 0.0;
	for (int n = 0; n < nebula_count; n++) {
		float ang_r     = max(nebula_angular_radii[n], 0.001);
		float proximity = 1.0 - clamp(length(EYEDIR - nebula_dirs[n]) / ang_r, 0.0, 1.0);
		float contrib   = nebula_colors[n].a * proximity;
		nebula_color   += nebula_colors[n].rgb * contrib;
		nebula_weight  += contrib;
	}
	if (nebula_weight > 0.001) {
		nebula_color /= nebula_weight;
	}

	// map_zoom = 0 → galaxy view (suppress nebula so silhouette reads cleanly)
	// map_zoom = 1 → zoomed in (full nebula color and detail)
	// gameplay renders at map_zoom = 0.0 (default)
	float nebula_opacity = mix(nebula_base_opacity, 1.0, map_zoom);
	rgb += nebula_color * cloud * nebula_opacity;

	// ── Procedural hash star field ───────────────────────────────────────────
	// Grid in spherical coordinates for uniform angular cell size everywhere.
	float grid_scale = 400.0;

	vec3 proc_dir = normalize(EYEDIR);

	// Convert to spherical coordinates for uniform cell distribution
	// azimuth: 0 to 2π around the equator
	// elevation: -π/2 to π/2 from south to north pole
	float azimuth   = atan(proc_dir.x, proc_dir.z);         // -π to π
	float elevation = asin(clamp(proc_dir.y, -1.0, 1.0));   // -π/2 to π/2

	// Grid in spherical space — cells are uniform angular size everywhere
	float az_cells  = grid_scale;
	float el_cells  = grid_scale * 0.5;   // half because elevation range is π vs 2π

	float az_norm   = (azimuth   / (2.0 * PI)) + 0.5;   // 0 to 1
	float el_norm   = (elevation / PI)          + 0.5;   // 0 to 1

	vec2 cell_2d    = floor(vec2(az_norm, el_norm) * vec2(az_cells, el_cells));
	vec3 cell_id    = vec3(cell_2d, 0.0);   // keep vec3 for hash compatibility

	// Hash this cell to get a deterministic value [0, 1]
	float cell_hash = hash(cell_id * 7.3 + vec3(13.7, 5.1, 9.3));

	// Galaxy structure: modulate density by galaxy position
	// Core region (player_galaxy_position near origin) is denser
	// Disc structure: Y component of galaxy position thins the field at edges
	float gal_dist   = length(player_galaxy_position.xz) / 100000.0;
	float core_factor = mix(proc_core_boost, 1.0, clamp(gal_dist, 0.0, 1.0));

	// Disc factor: stars thin out above/below galactic plane
	float disc_y      = abs(player_galaxy_position.y) / 8000.0;
	float disc_factor = 1.0 - clamp(disc_y * proc_disc_falloff, 0.0, 0.85);

	// Arm factor: subtle density increase in spiral arm directions
	// Uses the same noise infrastructure as nebula for coherence
	float arm_noise  = vnoise(proc_dir * 3.0 + player_galaxy_position * 0.000005);
	float arm_factor = mix(0.85, 1.0, arm_noise);

	// Combined star probability for this cell.
	// proc_star_density near 1.0 means sparse; lower means denser.
	float star_probability = (1.0 - proc_star_density) * core_factor * disc_factor * arm_factor;
	star_probability = clamp(star_probability, 0.0, 1.0);

	if (cell_hash < star_probability) {
		// Reconstruct star direction from spherical cell center
		vec2 cell_center_norm = (cell_2d + 0.5) / vec2(az_cells, el_cells);
		float star_az  = (cell_center_norm.x - 0.5) * 2.0 * PI;
		float star_el  = (cell_center_norm.y - 0.5) * PI;

		// Add sub-cell jitter from hash
		float jitter_az = (hash(cell_id + vec3(1.3, 0.0, 0.0)) - 0.5) * (2.0 * PI / az_cells) * 0.8;
		float jitter_el = (hash(cell_id + vec3(0.0, 2.7, 0.0)) - 0.5) * (PI / el_cells) * 0.8;
		star_az += jitter_az;
		star_el += jitter_el;

		// Convert back to Cartesian unit vector
		float cos_el = cos(star_el);
		vec3 star_dir = vec3(
		    sin(star_az) * cos_el,
		    sin(star_el),
		    cos(star_az) * cos_el
		);

		// Angular distance from this fragment to the star center
		float star_alignment = dot(proc_dir, star_dir);
		float angular_thresh  = PI / el_cells;

		if (star_alignment > 1.0 - angular_thresh) {
			// Color variation from cell hash
			float color_h = hash(cell_id * 3.1 + vec3(7.0, 2.0, 5.0));
			vec3 star_color = mix(
				vec3(1.0, 0.85, 0.7),
				vec3(0.8, 0.9, 1.0),
				color_h
			);

			// Brightness variation
			float brightness_h = hash(cell_id * 5.7 + vec3(1.0, 9.0, 3.0));
			float star_bright   = mix(0.3, 1.0, brightness_h) * proc_star_brightness;

			// Soft disc glow
			float t    = (star_alignment - (1.0 - angular_thresh)) / angular_thresh;
			float glow = smoothstep(0.0, 1.0, t) * star_bright;

			rgb += star_color * glow;
		}
	}
	// ── End procedural star field ────────────────────────────────────────────

	// ── Backdrop stars (rendered on top of nebula) ───────────────────────────
	//
	// Pixel-radius approach: apparent_size is now pixel radius.
	// We convert pixel radius → angular radius using fragment derivatives,
	// then use the same dot-product threshold math with a much tighter threshold.
	for (int i = 0; i < star_count; i++) {
		vec2 uv         = texel_uv(i);
		vec4 dir_size   = texture(star_directions, uv);
		vec4 col_bright = texture(star_colors,     uv);

		// Fast reject: star behind camera hemisphere
		if (dot(EYEDIR, dir_size.xyz) < 0.0) {
			continue;
		}

		float alignment = dot(EYEDIR, dir_size.xyz);

		// Convert pixel radius to angular radius.
		// We approximate the angular size of one pixel by assuming a typical
		// ~80° vertical FOV. This is coarse but keeps stars point-like and
		// consistent across the sky without needing projection matrices.
		float pixel_angle = 1.4 / viewport_size.y;

		float angular_radius = dir_size.w * pixel_angle;

		// Small-angle approximation: 1 - cos(θ) ≈ θ²/2
		// This keeps the same threshold math shape but with much smaller values.
		float threshold = angular_radius * angular_radius * 0.5;

		// Early exit: this fragment is outside the star's visible cone
		if (alignment < 1.0 - threshold) {
			continue;
		}

		// Smooth glow from center (alignment = 1.0) to edge (alignment = 1.0 - threshold)
		float t    = (alignment - (1.0 - threshold)) / max(threshold, 0.0001);
		float glow = smoothstep(0.0, 1.0, t) * col_bright.a;
		rgb += col_bright.rgb * glow;
	}

	COLOR = rgb;
}
