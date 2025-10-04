shader_type canvas_item;
render_mode unshaded, blend_mix;

// Declare screen texture explicitly for Godot 4 (gl_compat)
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// Parameters
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.6;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.35;
uniform float distortion_amount : hint_range(-0.5, 0.5) = 0.0; // disabled by default
uniform float chroma_amount : hint_range(0.0, 4.0) = 0.5;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.05;
uniform float time_scale = 1.0;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Centered coords for vignette/chromatic, but DO NOT warp UVs (no fisheye)
	vec2 centered = uv * 2.0 - 1.0;
	// No barrel/pincushion distortion applied; sample at original UVs
	vec2 uv_d = uv;
	// Chromatic aberration: sample RGB at slightly different offsets
	float ca = chroma_amount * 0.0025; // scale to reasonable pixel shift
	vec2 dir = normalize(centered + 1e-6);
	vec4 col;
	col.r = texture(SCREEN_TEXTURE, uv_d + dir * ca).r;
	col.g = texture(SCREEN_TEXTURE, uv_d).g;
	col.b = texture(SCREEN_TEXTURE, uv_d - dir * ca).b;
	col.a = 1.0;
	// Vignette (darker borders)
	float d = length(centered);
	float vig = smoothstep(1.0 - vignette_softness, 1.0, d);
	col.rgb *= mix(1.0, 1.0 - vignette_strength, vig);
	// Grain
	float t = TIME * time_scale;
	float n = rand(uv * vec2(1920.0,1080.0) + t);
	col.rgb = mix(col.rgb, col.rgb + (n - 0.5) * 0.15, grain_amount);
	COLOR = col;
}
