## Cycles glyph color through the full hue spectrum over time.
## phase_spread creates the rolling rainbow effect across characters.
@tool
extends RichTag

## Hue cycles per second. Negative = reverse direction.
@export var speed:        float = 1.0
@export_range(0.0, 1.0, 0.01) var saturation: float = 1.0
@export_range(0.0, 1.0, 0.01) var value:      float = 1.0
## Per-character hue offset as a fraction of the full spectrum.
## 0 = all same color. 0.1 = gradual rainbow. 1.0 = full spectrum per char.
@export_range(0.0, 1.0, 0.01) var phase_spread: float = 0.1

## Global rate multiplier. Set from markup via [tag speed=0.5].
## Multiplies this tag's frequency.
@export var effect_speed := 1.0
## Global intensity multiplier. Set from markup via [tag strength=2].
## Scales this tag's saturation.
@export var effect_strength := 1.0

func get_helper_funcs() -> String:
	return """vec3 _fx_rainbow_hsv2rgb(float h, float s, float v2) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(vec3(h) + K.xyz) * 6.0 - K.www);
	return v2 * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), s);
	}"""

func get_fragment() -> String:
	return """
	float hue = fract(TIME * %f + seed * %f);
	vec3  rgb = _fx_rainbow_hsv2rgb(hue, %f, %f);
	c.rgb *= mix(vec3(1.0), rgb, anim);""" % [speed * effect_speed, phase_spread, saturation * effect_strength, value]
