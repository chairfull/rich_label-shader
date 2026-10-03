@tool
class_name RichTag
extends RefCounted

## Map single-character symbol heads to tag names. Projects can populate this at
## runtime by calling `FlowLabelTag.register_symbol_head("!", "important")`.
const SYMBOL_HEADS: Dictionary[StringName, StringName] = {
	&"!": &"TODO",
	&"$": &"TODO",
	&"@": &"TODO",
}

## Easing function names available to tags. Tags should bake the chosen
## easing function directly into their GLSL by returning the function call
## (e.g. "%s(t)" % easing). These constants are string names of the
## corresponding `ease_*` functions emitted by the shader builder.
const EASE_SINE := "ease"
const EASE_OUT_CUBIC := "ease_out_cubic"
const EASE_IN_CUBIC := "ease_in_cubic"
const EASE_OUT_BACK := "ease_out_back"
const EASE_OUT_ELASTIC := "ease_out_elastic"
const EASE_IN_OUT_CUBIC := "ease_in_out_cubic"

## Font-variation request (e.g. {"embolden": 0.1} or {"italic": true}) that
## RichLabel merges into the glyph's FontVariation. Set from mutate_font().
var _tag_font_variation: Dictionary = {}

## Stable unique string ID for this effect class.
##
## Two instances of the same class share this ID regardless of their exported
## param values — params become uniforms, not baked code. Only bake something
## into the ID if it changes the *structure* of your GLSL (e.g. a "vertical vs
## horizontal" enum that determines which component you modify):
##
##   func get_effect_id() -> StringName:
##       return StringName("rise_%d" % direction)
##
## In that case the ShaderBuilder will emit a distinct function per variant.
func get_tag_id() -> StringName:
	return StringName(get_script().resource_path.get_file().get_basename())

func get_helper_funcs() -> String:
	return ""

## Complete GLSL vertex function. Must match this exact signature:
##
##   void fx_{effect_id}_vert(inout vec2 v, float it, float ot, float seed, vec2 origin, vec2 gsz)
##
##   v      — VERTEX in CanvasItem local space. Add offsets here to move the glyph.
##   it     — intro_t:  0.0 = just started animating in,  1.0 = fully visible
##   ot     — outro_t:  0.0 = just started animating out, 1.0 = fully hidden, -1.0 = inactive
##   seed   — stable per-glyph random float [0, 1]
##   origin — glyph draw origin (baseline position) in local space.
##            Use as pivot for scale/rotation: v = origin + (v - origin) * scale
##   gsz    — glyph pixel size vec2(width, ascent + descent)
func get_vertex() -> String:
	return ""

## Complete GLSL fragment function. Must match this exact signature:
##
##   void fx_{effect_id}_frag(inout vec4 c, float it, float ot, float seed)
##
##   c    — current RGBA color. Multiply c.a to fade; replace c.rgb to colorize.
##   it   — intro_t
##   ot   — outro_t (-1.0 = inactive)
##   seed — stable per-glyph random float [0, 1]
func get_fragment() -> String:
	return ""

## How many extra draw layers this tag contributes (0 = effect only, no layers).
func get_layer_count() -> int:
	return 0

## Per-layer configuration. Called for i in [0, get_layer_count()).
## Return a dictionary with any of the following keys:
##   sd_bias : float   — SDF threshold shift (>0 inflates = outline, 0 = fill)
##   color   : Color   — layer color
##   offset  : Vector2 — pixel offset (for drop shadows)
##   seed    : float   — per-layer random seed for animated effects
func get_layer_config(_i: int) -> Dictionary:
	return {}

## Called with positional args from the tag definition, e.g. [outline 3 black]
## passes args = [3, "black"]. Override to parse positional arguments.
func init_from_args(_args: Array) -> void:
	pass

## Default styling mutation hooks.
## Subclasses may override these to modify glyph font, size, or fill color
## based on tag parameters. The base implementation returns inputs unchanged.
func mutate_font(base_font: Font) -> Font:
	return base_font

func mutate_font_size(base_size: int) -> int:
	return base_size

## Override to tint the fill color for this span.
func mutate_color(base_color: Color) -> Color:
	return base_color

## Whether this tag's shader effects apply to inline nodes (images and
## scenes placed via ~id). The tag's vertex/fragment snippets run for the
## inline node when true. Layer-based tags (outline, glow, shadow) return
## false — extra draw layers are a glyph concept. Tags that only make sense
## for glyph SDF data can also opt out here.
func affects_inline() -> bool:
	return true
