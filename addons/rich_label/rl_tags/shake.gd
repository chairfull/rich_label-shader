## High-frequency positional jitter. Good for urgency, damage, rage, earthquake.
## Each glyph shakes independently (via seed) so it doesn't look like a rigid block.
@tool
extends RichTag

@export var amp: float = 3.0
## Jitter speed in updates per second. 20–30 feels frantic, 8–12 feels slow tremor.
@export var freq: float = 24.0

@export_enum("Both:0", "Horizontal:1", "Vertical:2") var axis: int = 0

## Global intensity multiplier. Set from markup via [tag strength=2]
## (or the `amp` alias). Multiplies this tag's amplitude/distance.
@export var effect_strength := 1.0
## Global rate multiplier. Set from markup via [tag speed=0.5].
## Multiplies this tag's frequency.
@export var effect_speed := 1.0

func get_vertex() -> String:
	var axes := "v.x += sx; v.y += sy;" if axis == 0 \
		else ("v.x += sx;" if axis == 1 else "v.y += sy;")
	return """
	// Two different seeds per axis so x and y don't move identically.
	float sx = sin(TIME * %.6f + seed * 127.1) * %.6f * anim;
	float sy = sin(TIME * %.6f + seed * 311.7 + 1.5) * %.6f * anim;
	%s""" % [freq * effect_speed, amp * effect_strength, freq * effect_speed, amp * effect_strength, axes]
