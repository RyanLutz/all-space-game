// Star screen-space glow pass — LOD 1 rendering.
//
// One fullscreen quad covers the viewport. The vertex stage writes POSITION
// directly in NDC (no MODEL/VIEW/PROJECTION applied), so the quad geometry
// is screen-locked regardless of where the host MeshInstance3D sits in the
// scene tree. The quad is placed at clip z = 0.999 (just inside the far
// plane) so the default depth test (LESS) fails wherever scene geometry
// wrote a closer fragment — i.e., opaque ships occlude the glow naturally.
// depth_draw_never keeps subsequent transparent passes (VFX) compositing
// normally on top of the stars.
//
// The fragment stage iterates the visible-star uniform array and, for each
// star, projects its world position to NDC using the renderer's built-in
// PROJECTION_MATRIX * VIEW_MATRIX. Those built-ins are bound per rendered
// frame, so the glow tracks instantly when the camera moves or rotates —
// no lag from a CPU-passed VP matrix that would only refresh on physics
// ticks.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

const int MAX_STARS = 256;

uniform int  star_count                                   = 0;
uniform vec4 star_pos_radius[MAX_STARS];   // xyz = world pos; w = world-space glow radius
uniform vec4 star_color[MAX_STARS];        // rgb = base color; a = per-star intensity multiplier

uniform float min_pixel_radius : hint_range(0.5,  16.0) = 2.0;
uniform float max_pixel_radius : hint_range(8.0, 256.0) = 64.0;
uniform float intensity        : hint_range(0.05,  8.0) = 1.5;
uniform float core_radius      : hint_range(0.01,  0.5) = 0.15;

void vertex() {
	// QuadMesh.size = (2,2) → VERTEX.xy spans [-1, 1], i.e. full NDC.
	// z = 0.999 puts us at the far plane so scene depth-test occludes us.
	POSITION = vec4(VERTEX.xy, 0.999, 1.0);
}

void fragment() {
	vec3  rgb    = vec3(0.0);
	float alpha  = 0.0;

	vec2 frag_px     = FRAGCOORD.xy;
	vec2 viewport_px = VIEWPORT_SIZE;

	// PROJECTION_MATRIX[1][1] = 1 / tan(fov_y / 2) — the y-axis projection
	// scale factor. Used to convert world-space radius at view-space depth
	// into NDC radius.
	float proj_y = PROJECTION_MATRIX[1][1];

	for (int i = 0; i < star_count; i++) {
		vec4 ps = star_pos_radius[i];
		vec3 world_pos    = ps.xyz;
		float world_radius = ps.w;

		// World → view space. Godot view-space looks down -Z, so visible
		// stars have view_pos.z < 0; cull anything at or behind the camera
		// plane to avoid divide-by-zero and back-projection artefacts.
		vec4 view_pos = VIEW_MATRIX * vec4(world_pos, 1.0);
		if (view_pos.z >= -0.001) {
			continue;
		}

		// View → clip → NDC.
		vec4 clip = PROJECTION_MATRIX * view_pos;
		if (clip.w <= 0.0) {
			continue;
		}
		vec3 ndc = clip.xyz / clip.w;

		// Off-screen cull with margin so glow halos still draw when the
		// star center is just past the screen edge.
		if (abs(ndc.x) > 1.5 || abs(ndc.y) > 1.5) {
			continue;
		}

		// NDC → pixel coords. Godot 4 (Vulkan): FRAGCOORD origin top-left,
		// NDC y = 1 at the top of the screen.
		vec2 star_px = vec2(
			(ndc.x * 0.5 + 0.5) * viewport_px.x,
			(1.0 - (ndc.y * 0.5 + 0.5)) * viewport_px.y
		);

		// Apparent screen radius in pixels.
		// world_radius / -view_pos.z → tangent of half-angular-size
		// × proj_y → NDC radius
		// × viewport_px.y * 0.5 → pixel radius
		float radius_px = (world_radius * proj_y / -view_pos.z) * viewport_px.y * 0.5;
		radius_px = clamp(radius_px, min_pixel_radius, max_pixel_radius);

		float d = distance(frag_px, star_px);
		float t = d / radius_px;
		if (t > 1.0) {
			continue;
		}

		// Two-component glow: tight bright core + wide soft halo.
		// Tracks the LOD 0 point shader's visual character so the LOD 0→1
		// handoff reads as a continuous brightness, not a pop.
		float core = 1.0 - smoothstep(0.0,         core_radius, t);
		float halo = 1.0 - smoothstep(core_radius, 1.0,         t);
		float glow = core + halo * 0.4;

		rgb   += star_color[i].rgb * glow * star_color[i].a * intensity;
		alpha = max(alpha, glow);
	}

	ALBEDO = rgb;
	ALPHA  = alpha;
}
