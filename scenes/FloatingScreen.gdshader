shader_type spatial;

uniform float power : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D screen_tex : hint_albedo;

void fragment() {
    vec2 uv = UV;

    // Vertical wipe effect
    float line = smoothstep(0.0, 1.0, uv.y / power);

    vec4 color = texture(screen_tex, uv) * line;

    // Flicker effect
    float flicker = 0.8 + 0.2 * sin(TIME * 50.0 + uv.y * 30.0);
    ALBEDO = color.rgb * flicker;
    ALPHA = color.a;
}