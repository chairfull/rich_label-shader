## Font size mutation. Integer directives ([24]) arrive as the kwarg `size`;
## float directives ([1.5]) as `scale`. Positional args are also accepted.
## Usage: [24]big] [1.5]scaled] [size 32 explicit]
@tool
extends RichTag

## Absolute font size in pixels. <= 0 disables it (falls back to scale).
@export var size := -1

## Multiplier applied to the current size when no absolute size is set.
@export_range(0.1, 8.0) var scale := 1.0

func init_from_args(args: Array) -> void:
	if args.size() >= 1:
		var v: Variant = args[0]
		if v is int or v is float:
			size = int(v)

func mutate_font_size(base_size: int) -> int:
	if size > 0:
		return size
	return maxi(1, int(roundf(base_size * scale)))
