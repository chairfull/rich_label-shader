class_name BenchWaveEffect
extends RichTextEffect
## Minimal animated BBCode effect for the benchmark: bobs each character.
## Having any active custom effect makes RichTextLabel re-render every frame,
## which is the fair comparison against RichLabel's per-frame shader tags.
var bbcode = "bwave"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	char_fx.offset.y = sin(char_fx.elapsed_time * 5.0 + float(char_fx.relative_index) * 0.6) * 8.0
	return true
