## Faux italic via a slanted font variation. Works for any font.
## Usage: [i]italic text]
@tool
extends RichTag

@export var size_delta: int = 0

func mutate_font(base_font: Font) -> Font:
	_tag_font_variation = {"italic": true}
	return base_font

func mutate_font_size(base_size: int) -> int:
	return base_size + int(size_delta)
