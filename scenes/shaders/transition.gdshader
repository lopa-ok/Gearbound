shader_type canvas_item;

uniform float progress : hint_range(0, 1);
uniform float diamondPixelSize = 20.0;

void fragment() {
    float xFraction = fract(FRAGCOORD.x / diamondPixelSize);
    float yFraction = fract(FRAGCOORD.y / diamondPixelSize);

    float xDistance = abs(xFraction - 0.5);
    float yDistance = abs(yFraction - 0.5);

    if (xDistance + yDistance > progress * 1.5) {
        discard;
    }

    COLOR = vec4(0.0, 0.0, 0.0, 1.0);
}