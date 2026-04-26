shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float point_size : hint_range(1.0, 16.0) = 2.0;

void vertex() {
    POINT_SIZE = point_size;
}

void fragment() {
    // Soft circular falloff inside the point quad
    vec2 uv    = POINT_COORD - vec2(0.5);
    float dist = length(uv) * 2.0;
    float alpha = smoothstep(1.0, 0.2, dist);

    ALBEDO   = COLOR.rgb;
    ALPHA    = COLOR.a * alpha;
    EMISSION = COLOR.rgb * COLOR.a;
}
