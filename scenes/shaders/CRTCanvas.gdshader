shader_type canvas_item;

// Godot 4 screen texture declaration
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// External controls (kept to match existing GDScript usage)
uniform float screen_alpha : hint_range(0.0, 1.0) = 1.0; // 0 = original, 1 = full effect
uniform float effect_strength : hint_range(0.0, 1.0) = 1.0; // global multiplier for the whole effect
uniform float noise_amount : hint_range(0.0, 1.0) = 0.05;  // grain level
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.03; // global brightness flicker

// CRT look controls
uniform float curvature : hint_range(0.0, 1.0) = 0.12; // barrel distortion amount
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.45;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.18;
uniform float scanline_density : hint_range(100.0, 3000.0) = 450.0; // higher = more lines
uniform float chroma_offset : hint_range(0.0, 3.0) = 0.6; // chromatic aberration strength

// VHS specific controls
uniform float vhs_wobble : hint_range(0.0, 1.0) = 0.4;       // horizontal UV wobble amount
uniform float vhs_wobble_freq : hint_range(0.5, 8.0) = 2.0;  // wobble frequency
uniform float vhs_tracking : hint_range(0.0, 1.0) = 0.15;    // horizontal line drift
uniform float vhs_dropout : hint_range(0.0, 1.0) = 0.03;     // dark/bright dropout streaks
uniform float vhs_bleed : hint_range(0.0, 1.0) = 0.25;       // horizontal bleeding (soft blur)

// Utility
float hash12(vec2 p) {
	p = fract(p * vec2(443.8975, 397.2973));
	p += dot(p, p.yx + 19.19);
	return fract(p.x * p.y);
}

vec2 barrel_distort(vec2 uv, float k) {
	// Map [0,1] -> [-1,1]
	vec2 p = uv * 2.0 - 1.0;
	float r2 = dot(p, p);
	p *= 1.0 + k * r2;
	return p * 0.5 + 0.5;
}

vec3 tap_screen(vec2 uv) {
	uv = clamp(uv, vec2(0.0), vec2(1.0));
	return texture(SCREEN_TEXTURE, uv).rgb;
}

void fragment() {
	// Base UVs
	vec2 uv0 = SCREEN_UV;

	// Estimate pixel resolution from screen pixel size (avoids passing from script)
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE; // approx viewport size in pixels

	// VHS horizontal wobble and tracking noise
	float t = TIME;
	float wob = (sin((uv0.y * 3.14159 * vhs_wobble_freq) + t * 2.1) * 0.0025 +
			   sin((uv0.y * 9.0) + t * 5.1) * 0.0009) * vhs_wobble * effect_strength;
	// Subtle per-scanline jitter influenced by pseudo-random hash of y
	float line_hash = hash12(vec2(floor(uv0.y * resolution.y), t * 0.5));
	float track = (line_hash - 0.5) * 0.0035 * vhs_tracking * effect_strength;

	// Apply wobble + tracking horizontally
	vec2 uv = uv0 + vec2(wob + track, 0.0);

	// CRT barrel distortion (after VHS wobble)
	uv = barrel_distort(uv, curvature * effect_strength);

	// Keep bounds to avoid wrapping after distortion
	bool in_bounds = uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
	vec2 uvc = clamp(uv, vec2(0.0), vec2(1.0));

	// Chromatic aberration (offset only in X to mimic shadow mask)
	vec2 ab = vec2(0.0015, 0.0) * chroma_offset * effect_strength;
	float r = texture(SCREEN_TEXTURE, uvc + ab).r;
	float g = texture(SCREEN_TEXTURE, uvc).g;
	float b = texture(SCREEN_TEXTURE, uvc - ab).b;
	vec3 col = vec3(r, g, b);

	// Horizontal color bleed (simple 3-tap blur)
	if (vhs_bleed > 0.0) {
		float px = 1.0 / max(resolution.x, 1.0);
		vec3 left = tap_screen(uvc + vec2(-2.0 * px, 0.0));
		vec3 right = tap_screen(uvc + vec2(2.0 * px, 0.0));
		col = mix(col, (col * 0.6 + (left + right) * 0.2), vhs_bleed * effect_strength);
	}

	// VHS dropouts (random horizontal bands that dim or brighten)
	float band_hash = hash12(vec2(floor(uv0.y * resolution.y * 0.5), floor(t * 8.0)));
	float dropout = smoothstep(0.85, 1.0, band_hash) * vhs_dropout * effect_strength;
	col *= 1.0 - dropout * 0.6;

	// Scanlines (animated a little to simulate refresh)
	float scan_phase = (uv.y + t * 0.5) * scanline_density;
	float scan_wave = 0.5 + 0.5 * sin(scan_phase);
	float scan_mix = mix(1.0, scan_wave, scanline_intensity * effect_strength);
	col *= scan_mix;

	// Vignette
	vec2 centered = uv - 0.5;
	float d = length(centered) * 1.4142; // normalized to [0, sqrt(2)] -> [0, ~1.4142]
	float vig = 1.0 - smoothstep(0.35, 0.95, d);
	col *= mix(1.0, vig, vignette_strength * effect_strength);

	// Global flicker and noise
	float flicker = 1.0 + (sin(TIME * 60.0) * flicker_amount * effect_strength);
	float n = (hash12(uv * resolution + t) - 0.5) * 2.0 * noise_amount * effect_strength; // [-1,1] noise
	col = col * flicker + n;

	// Mix with the original screen using the provided alpha; keep original alpha
	vec3 orig = texture(SCREEN_TEXTURE, uv0).rgb;
	vec3 mixed = mix(orig, col, clamp(screen_alpha, 0.0, 1.0));
	if (!in_bounds) {
		// Fade to black outside distorted bounds
		mixed *= 0.0;
	}
	COLOR = vec4(mixed, texture(SCREEN_TEXTURE, uv0).a);
}
