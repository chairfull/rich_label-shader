## Bobs the glyph up and down using a sine wave.
@tool
extends RichTag

@export_range(0.0, 2.0) var amplitude: float = 0.1   ## fraction of a 16px reference height
@export var frequency: float = 1.5    ## cycles per second
@export_range(0.0, 1.0, 0.01) var phase_spread: float = 0.5

## Global intensity multiplier. Set from markup via [tag strength=2]
## (or the `amp` alias). Multiplies this tag's amplitude/distance.
@export var effect_strength := 1.0
## Global rate multiplier. Set from markup via [tag speed=0.5].
## Multiplies this tag's frequency.
@export var effect_speed := 1.0

func get_vertex() -> String:
	return """
	float phase = seed * %.6f * TAU;
	float t = fx_time * %.6f * TAU + phase;
	v.y += sin(t) * %.6f * 16.0 * anim;""" % [phase_spread, frequency * effect_speed, amplitude * effect_strength]
