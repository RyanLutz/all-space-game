// Shield hit ripple — placeholder for art pass.
// Expands a glowing ring from u_hit_origin in local space, fading over ~1 second.
// u_hit_time < 0 means "no hit yet"; the fragment is fully transparent in that state.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec3  u_hit_origin    = vec3(0.0);
uniform float u_hit_time      = -1.0;
uniform vec4  u_color         : source_color = vec4(0.4, 0.7, 1.0, 0.8);
uniform float u_ripple_speed  = 2.5;
uniform float u_ripple_falloff = 1.8;

varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	vec3 albedo = vec3(0.0);
	float alpha = 0.0;

	if (u_hit_time >= 0.0) {
		float elapsed = TIME - u_hit_time;
		if (elapsed >= 0.0 && elapsed <= 1.0) {
			float dist       = length(v_local_pos - u_hit_origin);
			float ring_r     = elapsed * u_ripple_speed;
			float ring_width = 0.3;
			float ring       = 1.0 - clamp(abs(dist - ring_r) / ring_width, 0.0, 1.0);
			float fade       = 1.0 - pow(elapsed, u_ripple_falloff);
			albedo = u_color.rgb;
			alpha  = ring * fade * u_color.a;
		}
	}

	ALBEDO = albedo;
	ALPHA  = alpha;
}
