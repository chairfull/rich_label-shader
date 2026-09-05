## Each glyph flies in from a unique random direction on intro.
## Scatters outward on outro. The random angle is derived from seed,
## so it's stable across frames but different per character.
@tool
extends RichTag

@export var distance: float = 40.0

func get_vertex() -> String:
	return """
	float hidden = 1.0 - anim;
	float angle  = seed * TAU;  // unique direction per glyph, stable across frames
	vec2  dir    = vec2(cos(angle), sin(angle));
	v += dir * (hidden * %.6f);""" % distance
