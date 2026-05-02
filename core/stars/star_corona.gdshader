// Star corona shader — LOD 2 additive billboard halo.
//
// A single camera-facing QuadMesh sized to a multiple of the star's visual
// radius. The shader emits a soft additive disc with a tight bright core
// and a wide soft halo — same two-component model as the LOD 1 screen-pass
// glow, so the LOD 1→2 visual handoff stays continuous.
//
// Render mode: blend_add (additive composition over the surface and
// scene), depth_draw_never (never writes depth — combat VFX and other
// transparent passes still composite correctly on top), unshaded.
//
// Vertex stage applies the standard Godot 4 billboard-while-preserving-
// scale idiom so the corona faces the camera regardless of the host
// node's orientation, and a single uniform StarMesh.tscn does not need
// per-spawn billboard configuration.

shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec3  base_color : source_color = vec3(1.0, 0.7, 0.3);
uniform float intensity      : hint_range(0.0, 8.0) = 1.8;
uniform float inner_falloff  : hint_range(0.01, 1.0) = 0.18;
uniform float outer_falloff  : hint_range(0.1,  1.0) = 1.0;
// LOD crossfade weight: 0=invisible, 1=fully visible. Driven by StarRegistry.
uniform float blend_alpha    : hint_range(0.0, 1.0)  = 1.0;

void vertex() {
	// Billboard: replace MODELVIEW basis with the camera's inverse-view
	// basis (kills rotation), keep MODEL_MATRIX translation, then re-apply
	// the host node's per-axis scale so corona_scale on StarMesh actually
	// changes the disc size.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void fragment() {
	// Disc-space radius: 0 at quad center, 1 at quad edge.
	vec2 uv = UV - vec2(0.5);
	float d = length(uv) * 2.0;
	if (d > outer_falloff) {
		discard;
	}

	// Two-component falloff matches LOD 1 screen-pass character.
	float core = 1.0 - smoothstep(0.0,           inner_falloff, d);
	float halo = 1.0 - smoothstep(inner_falloff, outer_falloff, d);
	float a    = core + halo * 0.5;

	ALBEDO = base_color * intensity;
	// mix() crossfade: blend_alpha drives the LOD 1→2 spawn fade-in / LOD 2→1 fade-out.
	ALPHA  = mix(0.0, a, blend_alpha);
}
