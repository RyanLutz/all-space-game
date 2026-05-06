shader_type sky;
render_mode use_debanding;

// ─── Star catalog textures ───────────────────────────────────────────────────
// Packed by StarField.rebuild_skybox() once per warp.
// Each texel corresponds to one star (backdrop or destination).
//
// star_directions: RGBAF — (dir.x, dir.y, dir.z, apparent_size)
//   apparent_size is the angular dot-product threshold for the star glow.
// star_colors:     RGBA8  — (r, g, b, brightness)
//   brightness is the luminosity weight; blue giants > 1.0, red dwarfs < 0.5.
uniform sampler2D star_directions : filter_nearest, repeat_disable;
uniform sampler2D star_colors     : filter_nearest, repeat_disable;
uniform int star_count = 0;
uniform int tex_width  = 64;
uniform int tex_height = 64;

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

	// ── Backdrop stars (rendered on top of nebula) ───────────────────────────
	//
	// Each star is a texel in the star_directions / star_colors textures.
	// The inner loop dot-product check exits early for the vast majority of
	// stars in any given fragment (only a tiny angular region of the sky is
	// within any star's threshold), keeping GPU cost proportional to star
	// density visible in the fragment's direction.
	for (int i = 0; i < star_count; i++) {
		vec2 uv        = texel_uv(i);
		vec4 dir_size  = texture(star_directions, uv);
		vec4 col_bright = texture(star_colors,   uv);

		float alignment = dot(EYEDIR, dir_size.xyz);
		float threshold = dir_size.w;

		// Early exit: this fragment is outside the star's visible cone
		if (alignment < 1.0 - threshold) {
			continue;
		}

		// Smooth glow from center (alignment = 1.0) to edge (alignment = 1.0 - threshold)
		float t    = (alignment - (1.0 - threshold)) / max(threshold, 0.0001);
		float glow = smoothstep(0.0, 1.0, t) * col_bright.a;
		rgb += col_bright.rgb * glow;
	}

	COLOR = vec4(rgb, 1.0);
}
