// Полноэкранный пост-эффект: 15-битный цвет (5 бит на канал) + упорядоченный дизеринг Байера 4x4.
// Вешается на ColorRect во весь экран (см. scripts/ps1/ps1_post_fx.gd).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
// 31 = 5 бит на канал, как у PS1.
uniform float color_levels : hint_range(2.0, 255.0) = 31.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;

float bayer2(vec2 p) {
	return 2.0 * mod(p.x + p.y, 2.0) + p.y;
}

float bayer4(vec2 frag) {
	vec2 p = mod(floor(frag), 4.0);
	return (4.0 * bayer2(mod(p, 2.0)) + bayer2(floor(p * 0.5))) / 16.0;
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float d = (bayer4(FRAGCOORD.xy) - 0.5) * dither_strength;
	c = floor(c * color_levels + 0.5 + d) / color_levels;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
