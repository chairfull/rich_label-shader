## Tints the fill color for the tagged span.
@tool
extends RichTag

@export var color := Color.WHITE

func mutate_color(base_color: Color) -> Color:
	return Color(color, base_color.a)
