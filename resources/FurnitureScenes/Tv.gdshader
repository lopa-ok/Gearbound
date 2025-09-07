shader_type spatial;

render_mode unshaded, cull_disabled;

uniform vec3 glow_color = vec3(1.0, 1.0, 1.0); // cyan
uniform float glow_strength = 5.0;

void fragment() {
    EMISSION = glow_color * glow_strength;
    ALBEDO = glow_color; // optional, only for display
}