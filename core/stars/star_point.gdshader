// Star point shader — LOD 0 MultiMesh rendering.
//
// Each instance is a flat QuadMesh. The vertex stage projects the instance center
// to clip space and offsets the quad vertices in clip space so the star always
// occupies at least min_pixel_radius screen pixels regardless of world distance.
// Color and alpha come from per-instance custom data (INSTANCE_CUSTOM.rgba).
//
// Depth handling: all LOD 0 stars are pinned to a fixed depth just inside the
// far plane (0.0001 in Godot 4 Forward+ reversed-Z, same as star_screen_pass).
// This prevents hardware clipping for stars beyond the camera's far-plane distance
// and avoids depth-test failures against the sky clear value (0.0 in reversed-Z).
// Screen X/Y still derives from the real world position, so every star projects
// to the correct angular direction — the "star dome" approach.
//
// Render modes:
//   blend_add        — additive blending; overlapping stars accumulate brightness
//   depth_draw_never — transparent geometry; no depth write
//   unshaded         — no lighting; stars emit their own color
//   cull_disabled    — both faces of the quad render

shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform float min_pixel_radius : hint_range(0.5, 8.0) = 2.0;

void vertex() {
	// Project the instance center (local origin) to clip space.
	vec4 center_clip = PROJECTION_MATRIX * VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);

	// Discard vertices behind the camera — move them off-screen so they don't
	// produce artefacts after the perspective divide.
	if (center_clip.w <= 0.0) {
		POSITION = vec4(2.0, 2.0, 0.0, 1.0);
		return;
	}

	// Compute clip-space offset for min_pixel_radius pixels.
	// NDC spans [-1, 1] over VIEWPORT_SIZE pixels → 1 pixel = 2/VIEWPORT_SIZE NDC units.
	// In clip space (before w-divide), NDC offset must be premultiplied by w.
	// VERTEX.xy from a unit QuadMesh spans [-0.5, 0.5], so the factor is ×2 to reach ±1.
	float sx = VERTEX.x * 2.0 * min_pixel_radius * (2.0 / VIEWPORT_SIZE.x) * center_clip.w;
	float sy = VERTEX.y * 2.0 * min_pixel_radius * (2.0 / VIEWPORT_SIZE.y) * center_clip.w;

	// Pin to a fixed far-plane depth instead of the star's actual world depth.
	// Godot 4 Forward+ reversed-Z: near=1.0, far=0.0, sky clear=0.0.
	// Using 0.0001 (matching star_screen_pass) keeps every star safely inside the
	// far clip plane regardless of real distance and above the sky clear value so
	// the depth test reliably passes.
	POSITION = vec4(center_clip.x + sx, center_clip.y + sy, 0.0001 * center_clip.w, center_clip.w);
}

void fragment() {
	// Circular soft disc — discard corners of the quad.
	vec2 uv = UV - vec2(0.5);
	float d = length(uv) * 2.0;   // 0 at center, 1 at quad edge
	if (d > 1.0) discard;

	// Soft glow falloff from center.
	float glow = 1.0 - smoothstep(0.1, 1.0, d);

	ALBEDO = INSTANCE_CUSTOM.rgb;
	// INSTANCE_CUSTOM.a carries the LOD 0 crossfade weight (set by StarRegistry._update_multimesh()).
	// 1.0 = fully visible; fades toward 0 as the star transitions to the LOD 1 screen-pass.
	// mix() is the spec-required crossfade idiom — avoids hard pop at the LOD 0→1 boundary.
	ALPHA  = mix(0.0, glow, INSTANCE_CUSTOM.a);
}
