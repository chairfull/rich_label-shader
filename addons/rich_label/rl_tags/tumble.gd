## Gives each character a subtle pseudo-3D perspective-rotation wobble.
## The near edge of each quad widens and the far edge narrows, mimicking a card
## tilting slightly in-place. Characters each use their seed for a random phase
## so the rotations are de-synchronised.
##
## Usage:  [tumble]text]
##         [tumble amount=0.4 speed=0.8 perspective=2.0]text]
@tool
extends RichTag

## Rotation amplitude in radians. 0.3 ≈ 17°. Keep below ~0.7 to avoid inversion.
@export_range(0.0, 0.7, 0.01) var amount: float = 0.3

## Oscillation speed multiplier. Set to 0 for a static (fixed random) tilt.
@export_range(0.0, 4.0, 0.05) var speed: float = 1.0

## Perspective depth factor. Higher = more pronounced near/far size difference.
@export_range(0.0, 4.0, 0.05) var perspective: float = 1.5

## Global intensity multiplier. Set from markup via [tag strength=2]
## (or the `amp` alias). Multiplies this tag's amplitude/distance.
@export var effect_strength := 1.0
## Global rate multiplier. Set from markup via [tag speed=0.5].
## Multiplies this tag's frequency.
@export var effect_speed := 1.0

func get_tag_id() -> StringName:
	return &"tumble"

func get_vertex() -> String:
	# All float literals are baked; %.6f guarantees a decimal point so GLSL
	# never sees an ambiguous integer literal in a float expression.
	return ("""
float ph = seed * 6.28318530718;
float ay = cos(TIME * %.6f * 0.73 + ph)        * %.6f;
float ax = sin(TIME * %.6f * 1.07 + ph * 1.37) * %.6f * 0.55;

vec2 _ctr = origin + gsz * 0.5;
vec2 _p   = v - _ctr;

float _sy = sin(ay); float _cy = cos(ay);
float _px  = _p.x * _cy;
float _pz  = _p.x * _sy;

float _sx = sin(ax); float _cx = cos(ax);
float _py  =  _p.y * _cx + _pz * _sx;
float _pz2 = -_p.y * _sx + _pz * _cx;

float _z_norm = _pz2 / max(1.0, font_size);
float _zf = 1.0 / max(0.01, 1.0 - _z_norm * %.6f);
v = _ctr + vec2(_px, _py) * _zf;
""") % [speed * effect_speed, amount * effect_strength, speed * effect_speed, amount * effect_strength, perspective]
