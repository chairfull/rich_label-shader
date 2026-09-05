## Sine-driven horizontal shear (skew). The "sin" effect from the old README.
## The skew is applied proportional to how far each vertex is above the baseline,
## so the top of the glyph swings while the bottom stays planted — feels organic.
@tool
extends RichTag

## Shear factor. ~0.1–0.2 is subtle, ~0.4+ is dramatic.
@export_range(0.0, 1.0, 0.01) var amplitude: float = 0.15
@export var frequency:    float = 1.2
@export_range(0.0, 1.0, 0.01) var phase_spread: float = 0.3

func get_vertex() -> String:
	return ("""
	float phase  = seed * %f * TAU;
	float skew   = sin(TIME * %f * TAU + phase) * %f * anim;
	// Shear: x offset is proportional to distance above the baseline (origin.y).
	// Vertices below the baseline get a small negative offset; above get positive.
	float dist_above_baseline = origin.y - v.y;
	v.x += dist_above_baseline * skew;
	""") % [phase_spread, frequency, amplitude]
