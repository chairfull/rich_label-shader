## Drop shadow via SDF offset layer. Usage: [shadow 2 2] or [shadow x=2 y=2]
## Adds one layer with a pixel offset and slight SDF inflation.
@tool
extends RichTag

@export var x: float = 2.0
@export var y: float = 2.0
@export var spread: float = 0.02
@export var shadow_color: Color = Color(0, 0, 0, 0.5)

func init_from_args(args: Array) -> void:
	if args.size() >= 1: x = float(args[0])
	if args.size() >= 2: y = float(args[1])
	if args.size() >= 3:
		var c := Color.from_string(str(args[2]), Color(-1, -1, -1))
		if c != Color(-1, -1, -1): shadow_color = c

func get_layer_count() -> int:
	return 1

func get_layer_config(_i: int) -> Dictionary:
	return { sd_bias = spread, color = shadow_color, offset = Vector2(x, y) }

## Extra draw layers are a glyph concept; don't run on inline nodes.
func affects_inline() -> bool:
	return false
