## Slides the glyph from an offset position into its resting spot on intro.
## Reverses direction on outro. Works well paired with [fade].
@tool
extends RichTag

@export var amount: float = 20.0

## Direction the glyph arrives FROM, in degrees. 90 = rises from below.
@export_range(-180, 180) var dir := 0.0

## Global intensity multiplier. Set from markup via [tag strength=2]
## (or the `amp` alias). Multiplies this tag's amplitude/distance.
@export var effect_strength := 1.0

func get_vertex() -> String:
	var rad := deg_to_rad(dir)
	return """v += vec2(%.6f, %.6f) * (1.0 - anim);""" % [cos(rad) * amount * effect_strength, sin(rad) * amount * effect_strength]
