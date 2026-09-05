## Slides the glyph from an offset position into its resting spot on intro.
## Reverses direction on outro. Works well paired with [fade].
@tool
extends RichTag

@export var amount: float = 20.0

## Direction the glyph arrives FROM, in degrees. 90 = rises from below.
@export_range(-180, 180) var dir := 0.0

func get_vertex() -> String:
	var rad := deg_to_rad(dir)
	return """v += vec2(%.6f, %.6f) * anim;""" % [cos(rad) * amount, sin(rad) * amount]
