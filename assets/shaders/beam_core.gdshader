shader_type spatial;
render_mode depth_test_disabled, cull_disabled, unshaded, blend_add;

uniform vec4 beam_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float flicker_hz : hint_range(0.0, 60.0) = 14.0;
uniform float u_time_offset : hint_range(0.0, 6.283) = 0.0;
uniform float u_linger_progress : hint_range(0.0, 1.0) = 1.0;
uniform float u_hit_intensity : hint_range(0.0, 2.0) = 0.0;

varying float v_beam_dist;

void vertex() {
	// BoxMesh vertices range from -0.5 to +0.5 in local space.
	// Scale.z is stretched to beam length, so local Z is uniform 0..1.
	v_beam_dist = VERTEX.z + 0.5;
}

void fragment() {
	float t = TIME * flicker_hz + u_time_offset;
	float flicker = 1.0 + sin(t) * flicker_intensity;
	
	// Distance fade: tip always fades to zero
	float fade = smoothstep(1.0, 0.85, v_beam_dist);
	
	// Hit intensity flash decays over time
	float hit_flash = u_hit_intensity * exp(-(TIME - u_time_offset) * 10.0);
	if (u_hit_intensity > 0.0 && (TIME - u_time_offset) > 0.5) {
		hit_flash = 0.0;  // safety clamp
	}
	
	// Retina burn: oversaturate while fully on
	float intensity = 1.0 + u_linger_progress * 2.0;
	
	ALBEDO = beam_color.rgb * (flicker + hit_flash) * intensity;
	ALPHA = beam_color.a * u_linger_progress * fade;
}
