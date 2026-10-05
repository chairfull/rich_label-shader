extends Control
## Demo: effect gallery. One line per tag, all shader-side, zero per-frame CPU.

var _rows: Array = [
	["[wave amp=4 freq=3]wave: the classic]", "wave amp=4 freq=3"],
	["[rainbow]rainbow: fragment color cycle]", "rainbow"],
	["[shake strength=3]shake: jittery]", "shake strength=3"],
	["[blur radius=8]blur reveal: soft typewriter]", "blur radius=8 (head)"],
	["[shred distance=28]shred reveal: torn typewriter]", "shred distance=28 (head)"],
	["[u]underline] and [s]strikethrough] are shader quads]", "u / s"],
	["[outline 4 black]outline] + [glow]glow]", "outline 4 black / glow"],
	["[tint red]tint] and [fade]fade]", "tint red / fade"],
]

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 80
	box.offset_right = -80
	box.offset_top = 60
	box.offset_bottom = -40
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	var title := RichLabel.new()
	title.text = "effect gallery"
	title.font_size = 40
	box.add_child(title)

	for row in _rows:
		var line := RichLabel.new()
		line.text = row[0]
		line.font_size = 30
		line.custom_minimum_size = Vector2(0, 54)
		# Reveal heads for the blur/shred rows so the effect is visible.
		if "blur radius" in row[0]:
			line.head = "blur"
		elif "shred distance" in row[0]:
			line.head = "shred"
		box.add_child(line)
		line.play_intro()

		var cap := Label.new()
		cap.text = "  [" + row[1] + "]"
		cap.add_theme_font_size_override("font_size", 15)
		cap.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		box.add_child(cap)
