## Solid outline layer. Usage: [outline 3 black], [outline size=3], bare
## [outline] uses this tag's `outline_size` default.
##
## The glyph-wide "default outline" (applied to every glyph unless an explicit
## [outline] in the same span overrides it) is configured purely on this tag:
## set `mode` to COLOR/SHIFTED and tune `color`, `value`, and `hue_shift`.
##
## Thickness is limited by the font atlas itself: past roughly ~16px the MSDF
## threshold saturates its cell (and bitmap dilation reaches neighboring
## glyphs), so sizes are capped there — growing further silently stops.
## Cheap way to raise this ceiling: more Padding / higher MSDF Range on the
## font's Import settings.
@tool
extends RichTag

## Safety ceiling in px before SDF/atlas artifacts take over.
const MAX_PX := 16.0

## Mode governing the glyph-wide default outline.
enum Mode {
	NONE,	## No automatic outline on glyphs without an explicit [outline].
	COLOR,	## Every glyph outlined with `outline_color`.
	SHIFTED,## Outline derived from each glyph's fill: darkened (or lightened if
			## the fill is already dark), with optional hue rotation.
}

## Thickness (px). Caps at MAX_PX in the shader path.
@export_range(0.5, 32.0, 0.5) var outline_size: float = 4.0
@export var outline_color: Color = Color.BLACK
## Mode for the automatic outline behind every glyph.
@export var mode: Mode = Mode.NONE
## Hue rotation (degrees) applied to the outline in SHIFTED mode.
@export_range(-180.0, 180.0, 0.1) var hue_shift: float = 0.0
## Lightness of SHIFTED outlines relative to the fill:
## -1.0 = pure white, +1.0 = pure black, in between = the fill lerped toward
## white/black (a tinted darker/lighter version). Hue shift applies afterwards.
@export_range(-1.0, 1.0, 0.01) var value: float = 0.55

func init_from_args(args: Array) -> void:
	if args.size() >= 1: outline_size = float(args[0])
	if args.size() >= 2:
		var c := Color.from_string(str(args[1]), Color(-1, -1, -1))
		if c != Color(-1, -1, -1): outline_color = c

func get_layer_count() -> int:
	return 1

func get_layer_config(_i: int) -> Dictionary:
	var sz := minf(maxf(0.5, outline_size), MAX_PX)
	# radius_px drives the bitmap coverage-dilation path; sd_bias the MSDF one.
	return { sd_bias = sz * 0.025, color = outline_color, offset = Vector2.ZERO, radius_px = sz }

## Resolves the outline color for a glyph's final fill color, honoring `mode`.
## Used by RichLabel for the glyph-wide default outline.
func resolve_color(fill: Color) -> Color:
	match mode:
		Mode.COLOR:
			return outline_color
		Mode.SHIFTED:
			return RTUtils.shift_color(fill, value, hue_shift)
		_:
			return Color.BLACK

## Whether the glyph-wide default outline is enabled (mode != NONE).
func default_is_active() -> bool:
	return mode != Mode.NONE
