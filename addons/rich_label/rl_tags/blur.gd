## Blur reveal: glyphs emerge from a blur on intro and dissolve back into one
## on outro, with a touch of alpha fade at the extremes. Mostly blur, per the
## typewriter brief — pair with [fade] for more alpha.
##
## Usage: [blur]text]  —  [blur radius=8 fade_amount=0.5]text]
## Put [blur] first when stacking ([blur][rainbow]) so color tags tint the mix.
@tool
extends RichTag

## Blur radius in pixels at full blur (anim = 0).
@export_range(0.0, 12.0, 0.5) var radius := 6.0
## Extra alpha fade at the fully-hidden ends: 0 = pure blur, 1 = full fade.
@export_range(0.0, 1.0, 0.01) var fade_amount := 0.35
## Global intensity multiplier: [blur strength=2] blurs twice as far.
@export var effect_strength := 1.0

func get_fragment() -> String:
	return """
	{
		float bt = clamp(1.0 - anim, 0.0, 1.0);
		if (bt > 0.001) {
			vec2 bpx = TEXTURE_PIXEL_SIZE * %.6f * bt;
			vec4 btex = tex * 4.0;
			btex += texture(TEXTURE, UV + vec2( bpx.x,  0.0));
			btex += texture(TEXTURE, UV + vec2(-bpx.x,  0.0));
			btex += texture(TEXTURE, UV + vec2( 0.0,  bpx.y));
			btex += texture(TEXTURE, UV + vec2( 0.0, -bpx.y));
			btex += texture(TEXTURE, UV + vec2( bpx.x,  bpx.y)) * 0.5;
			btex += texture(TEXTURE, UV + vec2(-bpx.x,  bpx.y)) * 0.5;
			btex += texture(TEXTURE, UV + vec2( bpx.x, -bpx.y)) * 0.5;
			btex += texture(TEXTURE, UV + vec2(-bpx.x, -bpx.y)) * 0.5;
			btex /= 10.0;
			vec4 bc;
			get_text_color(bc, glyph, btex, TEXTURE_PIXEL_SIZE, UV, layer);
			bc.a *= mix(1.0 - %.6f, 1.0, anim);
			c = mix(bc, c, easeout_cubic(anim));
		}
	}""" % [radius * effect_strength, fade_amount]
