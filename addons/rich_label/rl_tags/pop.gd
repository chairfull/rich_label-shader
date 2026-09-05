## Scales the glyph in from zero (or a custom start_scale) on intro.
## Shrinks back to zero on outro. Optionally fades simultaneously.
## OUT_BACK easing is the default — gives a satisfying overshoot pop.
@tool
extends RichTag

## Scale at t=0. 0.0 = appears from nothing. 0.5 = appears from half size.
@export_range(0.0, 1.0, 0.01) var start_scale: float = 0.0

## How much the alpha is also faded in alongside the scale (0 = scale only).
@export_range(0.0, 1.0, 0.01) var fade_amount: float = 0.8

func get_vertex() -> String:
	return """
	float scale = mix(%f, 1.0, anim);
	// Scale around the horizontal center of the glyph at baseline height.
	// This keeps the glyph anchored at its baseline as it grows.
	vec2 pivot = origin + vec2(gsz.x * 0.5, 0.0);
	v = pivot + (v - pivot) * scale;""" % [start_scale]

func get_fragment() -> String:
	return """
	// Use linear fade here (not the same easing) so OUT_BACK overshoot
	// doesn't cause alpha to briefly go above 1.0 and look wrong.
	c.a *= mix(1.0, clamp(anim / 0.5, 0.0, 1.0), %f);""" % [fade_amount]
	
