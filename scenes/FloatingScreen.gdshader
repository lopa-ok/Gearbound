shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// Video texture from VideoStreamPlayer
uniform sampler2D screen_tex;

// Fade control from script
uniform float screen_alpha : hint_range(0.0, 1.0) = 1.0;

// Fit controls (set from floating_screen.gd)
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec4 bar_color = vec4(0.0, 0.0, 0.0, 1.0);

// Reveal mask: 0 -> thin line, 1 -> fully revealed
uniform float reveal_amount : hint_range(0.0, 1.0) = 1.0;
// true = reveal grows along height (mask on Y), false = along width (mask on X)
uniform bool reveal_axis_vertical = true;
// soft edge thickness in UV units (0..0.2 recommended)
uniform float reveal_softness : hint_range(0.0, 0.2) = 0.0;

void fragment() {
	// Base UVs
	vec2 uv = UV;
	// When looking at the back face, flip U so the image is not mirrored
	if (!FRONT_FACING) {
		uv.x = 1.0 - uv.x;
	}
	// Center-scale the video according to uv_scale
	vec2 cuv = uv * uv_scale + (vec2(1.0) - uv_scale) * 0.5;
	// If outside the [0,1] range, draw bars; else sample video
	bvec2 out_range = bvec2(cuv.x < 0.0 || cuv.x > 1.0, cuv.y < 0.0 || cuv.y > 1.0);
	vec4 color = (out_range.x || out_range.y) ? bar_color : texture(screen_tex, cuv);
	// Reveal mask based on mesh UV (not cuv), from center outwards along chosen axis
	float axis_uv = reveal_axis_vertical ? uv.y : uv.x;
	float dist = abs(axis_uv - 0.5);
	float ra = clamp(reveal_amount, 0.0, 1.0);
	float mask;
	if (ra >= 0.999) {
		// Fully revealed: no fade anywhere
		mask = 1.0;
	} else {
		float half_span = 0.5 * ra;
		if (reveal_softness <= 0.0001) {
			// Hard edge line reveal (no blur)
			mask = step(dist, half_span);
		} else {
			float edge0 = max(0.0, half_span - reveal_softness);
			float edge1 = half_span;
			mask = 1.0 - smoothstep(edge0, edge1, dist);
		}
	}
	ALBEDO = color.rgb;
	ALPHA = color.a * screen_alpha * mask;
}