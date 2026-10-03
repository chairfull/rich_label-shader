## Each glyph flies in from a unique random direction on intro.
## Scatters outward on outro. The random angle is derived from seed,
## so it's stable across frames but different per character.
@tool
extends RichTag

@export var distance: float = 40.0

## Global intensity multiplier. Set from markup via [tag strength=2]
## (or the `amp` alias). Multiplies this tag's amplitude/distance.
@export var effect_strength := 1.0

func get_vertex() -> String:
	return """
	float hidden = 1.0 - anim;
	float angle  = seed * TAU;  // unique direction per glyph, stable across frames
	vec2  dir    = vec2(cos(angle), sin(angle));
	v += dir * (hidden * %.6f);""" % (distance * effect_strength)
