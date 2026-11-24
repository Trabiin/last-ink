shader_type canvas_item;
render_mode unshaded;
// Pixel-art effects (scripts/fx_layer.gd): the effects are drawn on their own at one texture pixel per world
// pixel, and this turns that drawing into pixel art before it lands on screen:
//  - every colour snaps to the nearest colour of the FX palette (the style palette plus a few accent tints),
//  - see-through comes in flat steps (a sixth, a third, two thirds, solid), so a soft glow reads as bands
//    and a big faint area is one even wash instead of turning to mush,
//  - the night tint the world canvas applied is taken back out (the effects are light), and part of it put
//    back so a spell at night still sits in the night.
uniform sampler2D palette : filter_nearest;
uniform int palette_size = 1;
uniform vec3 world_tint = vec3(1.0);
uniform float tint_kept = 0.45;
// 1: the faintest band dissolves into an ordered 4x4 dither of scattered pixels instead. Off: over a big area
// (a heal ring, where a tech lands) scattered pixels read as a mesh.
uniform float dither = 0.0;

const float LEVELS = 3.0;
const float BOOST = 1.5;  // effects were drawn soft for a smooth screen: most of a shape lands solid here
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.03) {
		discard;
	}
	ivec2 p = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
	float th = (BAYER[(p.y % 4) * 4 + (p.x % 4)] + 0.5) / 16.0;
	// See-through comes in three steps (a third, two thirds, solid), never a smooth blur.
	float ab = min(c.a * BOOST, 1.0);
	// Only the very faintest dissolves into scattered pixels; above that each pixel takes the nearest flat
	// step, so a wash is one even tint (no checkerboard over it).
	float faint = dither > 0.5 ? (ab * LEVELS * 2.0 > th ? 1.0 / LEVELS : 0.0) : (ab > 0.04 ? 0.5 / LEVELS : 0.0);
	float a = ab < 0.5 / LEVELS ? faint : floor(ab * LEVELS + 0.5) / LEVELS;
	if (a <= 0.0) {
		discard;
	}
	vec3 rgb = clamp(c.rgb / c.a / max(world_tint, vec3(0.08)), 0.0, 1.0);
	vec3 best = rgb;
	float bd = 1e9;
	for (int i = 0; i < palette_size; i++) {
		vec3 q = texelFetch(palette, ivec2(i, 0), 0).rgb;
		vec3 d = rgb - q;
		float rm = (rgb.r + q.r) * 0.5;  // "redmean": a cheap distance closer to how eyes judge colour
		float dist = (2.0 + rm) * d.r * d.r + 4.0 * d.g * d.g + (3.0 - rm) * d.b * d.b;
		if (dist < bd) {
			bd = dist;
			best = q;
		}
	}
	COLOR = vec4(best * mix(vec3(1.0), world_tint, tint_kept), a);
}
