## Uniform glow halo around glyphs — no directional offset, eased gradient
## falloff instead of a hard rim.
##   MSDF:   the distance field itself is dilated by a tap kernel
##           (`size_px` reach), softened over `thickness`.
##   bitmap: halo radius = `size_px`, stepped gradient rings.
## Peak opacity = glow_color.a * intensity.
@tool
extends RichTag

## Mode governing the glyph-wide default glow.
enum Mode {
	NONE,	## No automatic glow on glyphs without an explicit [glow].
	COLOR,	## Every glyph glows with `glow_color`.
	SHIFTED,## Glow derived from each glyph's fill (value slider toward white
			## reads as luminous), with optional hue rotation.
}

## Falloff width (MSDF, in SDF-range units). Bigger = softer, wider.
@export_range(0.05, 0.49, 0.01) var thickness := 0.38
## Halo reach in pixels (bitmap rings / MSDF kernel distance).
@export_range(0.5, 16.0, 0.5) var size_px := 6.0
## Peak brightness multiplier applied to the glow color's alpha.
@export_range(0.0, 1.0, 0.01) var intensity := 0.8
@export var glow_color: Color = Color(1.0, 0.45, 0.15)
## Mode for the automatic glow behind every glyph.
@export var mode: Mode = Mode.NONE
## Hue rotation (degrees) applied to the glow in SHIFTED mode.
@export_range(-180.0, 180.0, 0.1) var hue_shift: float = 0.0
## Lightness of SHIFTED glows relative to the fill: -1.0 = pure white
## (luminous), +1.0 = pure black, in between = tinted toward either.
@export_range(-1.0, 1.0, 0.01) var value: float = -0.35

func init_from_args(args: Array) -> void:
	if args.size() >= 1:
		var c := Color.from_string(str(args[0]), Color(-1, -1, -1))
		if c != Color(-1, -1, -1): glow_color = c
	if args.size() >= 2:
		size_px = float(args[1])

func get_layer_count() -> int:
	return 1

# No sd_bias (never floods), zero offset (uniform around the glyph), and the
# intensity rides the layer color's alpha — no shader changes needed.
func get_layer_config(_i: int) -> Dictionary:
	return {
		sd_bias = 0.0,
		color = Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * intensity),
		offset = Vector2.ZERO,
		feather = thickness,
		radius_px = size_px,
	}

## Resolves the glow color for a glyph's final fill color, honoring `mode`.
## Used by RichLabel for the glyph-wide default glow.
func resolve_color(fill: Color) -> Color:
	match mode:
		Mode.COLOR:
			return glow_color
		Mode.SHIFTED:
			return RTUtils.shift_color(fill, value, hue_shift)
		_:
			return Color(1.0, 0.45, 0.15)

## Whether the glyph-wide default glow is enabled (mode != NONE).
func default_is_active() -> bool:
	return mode != Mode.NONE

## Extra draw layers are a glyph concept; don't run on inline nodes.
func affects_inline() -> bool:
	return false
