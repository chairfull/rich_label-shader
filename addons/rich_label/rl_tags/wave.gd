## Continuous sine wave oscillation. Default is vertical (the classic bbcode wave).
## phase_spread controls how much each glyph is staggered, giving the ripple effect.
@tool
extends RichTag

@export var amplitude:    float = 4.0
@export var frequency:    float = 1.5   ## Cycles per second
## Per-character phase offset as a fraction of TAU.
## 0 = all glyphs move in sync. 0.4 = nice rolling wave.
@export_range(0.0, 1.0, 0.01) var phase_spread: float = 0.4

@export_enum("Vertical:0", "Horizontal:1", "Circular:2") var axis: int = 0

## Global intensity multiplier. Set from markup via [tag strength=2]
## (or the `amp` alias). Multiplies this tag's amplitude/distance.
@export var effect_strength := 1.0
## Global rate multiplier. Set from markup via [tag speed=0.5].
## Multiplies this tag's frequency.
@export var effect_speed := 1.0

func get_vertex() -> String:
	return """
	float phase  = seed * %f * TAU;
	float t      = TIME * %f * TAU + phase;
	float s      = sin(t) * %f * anim;
	if      (%d == 0) { v.y += s; }
	else if (%d == 1) { v.x += s; }
	else {
		v.y += sin(t) * %f * anim;
		v.x += cos(t) * %f * anim;
	}""" % [phase_spread, frequency * effect_speed, amplitude * effect_strength, axis, axis, amplitude * effect_strength, amplitude * effect_strength]
