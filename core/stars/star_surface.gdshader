// Star surface shader — LOD 2 plasma rendering.
//
// Used by all three layered spheres of a StarMesh:
//   - Core sphere      (layer_alpha = 1.0, slow flow, opaque base body)
//   - Inner atmosphere (layer_alpha < 1, faster flow, transparent overlay)
//   - Outer atmosphere (layer_alpha < 1, slowest flow but counter-rotated,
//                       wider noise scale → soft outermost wisps)
//
// The shader samples 3D fractal-Brownian-motion noise in object-local
// space using a varying carried from the vertex stage. Object-local
// sampling means the noise pattern is stable on the sphere surface and
// does not swim when the camera moves — only TIME advances the flow.
//
// Render mode: blend_mix + depth_draw_opaque means the core writes depth
// (opaque-looking), atmospheres composite on top with alpha. unshaded
// because stars emit their own light; the OmniLight3D on the StarMesh
// lights other geometry, not the star itself.

shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque;

uniform vec3  base_color : source_color = vec3(1.0, 0.5, 0.2);
uniform float layer_alpha     : hint_range(0.0, 1.0)  = 1.0;
uniform float noise_scale     : hint_range(0.1, 16.0) = 2.5;
uniform float flow_speed      : hint_range(0.0,  1.0) = 0.05;
uniform float rotation_speed  : hint_range(-1.0, 1.0) = 0.0;
uniform float brightness      : hint_range(0.0,  4.0) = 1.4;
uniform float contrast        : hint_range(0.5,  4.0) = 1.6;
// LOD 1→2 crossfade: driven by StarRegistry each frame (0=invisible, 1=fully visible).
// Default 1.0 so the shader is correct when previewed outside StarRegistry.
uniform float blend_alpha     : hint_range(0.0, 1.0)  = 1.0;

// Object-local normalized direction from sphere center. Stable across camera
// motion; only TIME drives the noise field.
varying vec3 v_obj_dir;

void vertex() {
	v_obj_dir = normalize(VERTEX);
}

// 3D value-noise hash. Cheap, no texture lookup.
float hash13(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z
	);
}

// 4-octave fBm. Plenty of detail without a texture lookup; cheap on GPU.
float fbm(vec3 p) {
	float a = 0.0;
	float w = 0.5;
	for (int i = 0; i < 4; i++) {
		a += w * noise3(p);
		p *= 2.07;
		w *= 0.5;
	}
	return a;
}

void fragment() {
	// Slow rotation around the local Y axis; each layer is given a different
	// rotation_speed so atmospheres visibly drift relative to the core.
	float ang = TIME * rotation_speed;
	float c = cos(ang);
	float s = sin(ang);
	vec3 dir = vec3(
		 c * v_obj_dir.x - s * v_obj_dir.z,
		 v_obj_dir.y,
		 s * v_obj_dir.x + c * v_obj_dir.z
	);

	// Sample fBm in two slightly offset domains and blend by TIME for a
	// roiling, never-quite-repeating plasma flow.
	float t = TIME * flow_speed;
	vec3 p1 = dir * noise_scale + vec3(0.0,  t,        0.0);
	vec3 p2 = dir * noise_scale + vec3(t,    0.0,     -t * 0.7);
	float v = mix(fbm(p1), fbm(p2), 0.5 + 0.5 * sin(t * 0.5));

	// Boost contrast around the midpoint, then re-clamp.
	v = clamp((v - 0.5) * contrast + 0.5, 0.0, 1.0);

	// Base luminance: never fully dark even in the dimmest patches.
	vec3 col = base_color * (0.5 + v * brightness);

	// Hot peaks — bias the brightest fraction toward white-hot for the
	// "sunspot inverse" look real plasma has.
	col = mix(col, vec3(1.6, 1.55, 1.35), smoothstep(0.82, 1.0, v));

	ALBEDO   = col;
	EMISSION = col;
	// mix() crossfade: blend_alpha drives the LOD 1→2 spawn fade-in / LOD 2→1 despawn fade-out.
	ALPHA    = mix(0.0, layer_alpha, blend_alpha);
}
