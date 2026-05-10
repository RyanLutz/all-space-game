shader_type spatial;

uniform vec4 color_base    : source_color = vec4(1.0);
uniform vec4 color_accent  : source_color = vec4(0.5);
uniform vec4 color_glow    : source_color = vec4(0.0, 0.5, 1.0, 1.0);
uniform vec4 color_window  : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;

uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float metallic : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec4 albedo = texture(albedo_texture, UV);
    vec3 col = albedo.rgb;
    col = mix(col, color_base.rgb,   COLOR.r);
    col = mix(col, color_accent.rgb, COLOR.g);
    col = mix(col, color_glow.rgb,   COLOR.b);
    col = mix(col, color_window.rgb, COLOR.a);
    ALBEDO = col;
    ROUGHNESS = roughness;
    METALLIC = metallic;
    EMISSION = color_glow.rgb * COLOR.b * 0.6;
}
