shader_type spatial;

uniform vec4 color_primary : source_color = vec4(0.3, 0.5, 0.7, 1.0);
uniform vec4 color_trim : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 color_accent : source_color = vec4(1.0, 0.8, 0.0, 1.0);
uniform vec4 color_glow : source_color = vec4(0.3, 0.5, 1.0, 1.0);

uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float metallic : hint_range(0.0, 1.0) = 0.3;
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;

void fragment() {
    // Read vertex colors (set in Blender)
    float r = COLOR.r;
    float g = COLOR.g;
    float b = COLOR.b;
    float a = COLOR.a;

    // Blend albedo based on vertex color channels
    // Unweighted areas fall back to dark neutral
    float neutral_weight = 1.0 - clamp(r + g + b + a, 0.0, 1.0);

    vec3 albedo = color_primary.rgb * r
                + color_trim.rgb    * g
                + color_accent.rgb  * b
                + vec3(0.08)        * neutral_weight;

    ALBEDO = albedo;
    ROUGHNESS = roughness;
    METALLIC = metallic;

    // Glow emission from alpha channel
    EMISSION = color_glow.rgb * a * emission_energy;
}
