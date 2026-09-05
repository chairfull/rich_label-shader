## Faux bold via a font variation embolden. Works for any font — no bold
## variant files required. Usage: [b]bold text]
@tool
extends RichTag

@export var size_delta: int = 0

func mutate_font(base_font: Font) -> Font:
	_tag_font_variation = {"embolden": RTUtils.FAUX_BOLD_EMBOLDEN}
	return base_font

func mutate_font_size(base_size: int) -> int:
	return base_size + int(size_delta)
