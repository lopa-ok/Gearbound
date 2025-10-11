// Torn-paper UI shader (Godot 4 CanvasItem)
shader_type canvas_item;

// Paper base
uniform bool use_base_tex = false;
uniform sampler2D base_tex : source_color;
uniform vec4 paper_color : source_color = vec4(0.97, 0.95, 0.90, 1.0);

// Edge masking
uniform bool has_noise = false;
uniform sampler2D noise_tex : source_color;
uniform float noise_scale = 4.0;
uniform float edge_width = 0.06;      // logical thickness of torn border (0..0.5)
uniform float edge_softness = 0.02;   // feathering at edge (0..0.25)

// Grain/detail
uniform float grain_strength = 0.0;   // 0..0.3

// Soft shadow
uniform bool draw_shadow = true;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float shadow_strength = 0.35; // 0..1 (alpha of shadow)
uniform float shadow_spread = 0.08;   // extra halo thickness beyond tear
uniform vec2 shadow_offset = vec2(0.008, 0.01);

float rand(vec2 p) { return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453); }

float edge_mask(vec2 uv) {
	// Distance to nearest rect edge in UV space
	float e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float n = 0.5;
	if (has_noise) {
		n = texture(noise_tex, uv * noise_scale).r;
	}
	// Randomize thickness with noise around edge_width
	float th = edge_width * mix(0.6, 1.4, n);
	return smoothstep(th, th + edge_softness, e);
}

void fragment() {
	vec2 uv = UV;
	// Primary mask
	float m = edge_mask(uv);

	// Base paper color/texture
	vec4 base_col = paper_color;
	if (use_base_tex) {
		base_col = texture(base_tex, uv);
	}
	// Subtle animated grain
	if (grain_strength > 0.0 && has_noise) {
		float g = texture(noise_tex, uv * (noise_scale * 3.7) + vec2(TIME * 0.03)).r;
		base_col.rgb *= 1.0 + (g - 0.5) * grain_strength;
	}

	// Shadow computed by sampling mask at offset and spreading it a bit
	float shadow_alpha = 0.0;
	if (draw_shadow) {
		vec2 suv = uv - shadow_offset;
		float ms = edge_mask(suv);
		// Invert mask to get outside region, then expand with spread
		float outside = 1.0 - m;
		float halo = smoothstep(0.0, shadow_spread, outside) * ms;
		shadow_alpha = halo * shadow_strength;
	}

	// Composite: draw shadow where paper is transparent, draw paper where mask is 1
	float out_a = max(m, shadow_alpha);
	vec3 out_rgb = base_col.rgb * m + shadow_color.rgb * shadow_alpha * (1.0 - m);
	COLOR = vec4(out_rgb, out_a);
}
