## Shredder reveal: odd pixel rows slide left, even rows slide right, with the
## displacement following the intro/outro animation. Glyphs tear into
## horizontal slices and reassemble as they reveal.
##
## Usage: [shred]text]  —  [shred distance=32 slice=2]text]
## Put [shred] first when stacking ([shred][rainbow]) so color tags tint the mix.
@tool
extends RichTag

## Max horizontal displacement in pixels at full shred (anim = 0).
@export_range(0.0, 64.0, 0.5) var distance := 24.0
## Slice height in screen pixels. 1 = every pixel row alternates direction.
@export_range(1.0, 8.0, 1.0) var slice := 1.0
## Extra alpha fade at the fully-hidden ends: 0 = pure shred, 1 = full fade.
@export_range(0.0, 1.0, 0.01) var fade_amount := 0.35
## Global intensity multiplier: [shred strength=2] shreds twice as far.
@export var effect_strength := 1.0

func get_fragment() -> String:
	return """
	{
		float sh = clamp(1.0 - anim, 0.0, 1.0);
		if (sh > 0.001) {
			float srow = floor(FRAGCOORD.y / %.6f);
			float sdir = 1.0 - mod(srow, 2.0) * 2.0;
			vec2 suv = UV + vec2(sdir * %.6f * sh * TEXTURE_PIXEL_SIZE.x, 0.0);
			vec4 stex = texture(TEXTURE, suv);
			vec4 sc;
			get_text_color(sc, glyph, stex, TEXTURE_PIXEL_SIZE, UV, layer);
			sc.a *= mix(1.0 - %.6f, 1.0, anim);
			c = mix(sc, c, easeout_cubic(anim));
		}
	}""" % [slice, distance * effect_strength, fade_amount]
