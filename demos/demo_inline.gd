extends Control
## Demo: inline images (~id) and Control scenes (~scene_id).
## Tags apply to inline content: the card waves and the icon glows.

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 80
	box.offset_right = -80
	box.offset_top = 80
	box.add_theme_constant_override("separation", 30)
	add_child(box)

	var title := RichLabel.new()
	title.text = "inline content"
	title.font_size = 40
	box.add_child(title)

	var L1 := RichLabel.new()
	L1.font_size = 30
	L1.custom_minimum_size = Vector2(0, 60)
	L1.text = "an inline image: ~test_icon and it flows with the text."
	L1.play_intro()
	box.add_child(L1)

	var L2 := RichLabel.new()
	L2.font_size = 30
	L2.custom_minimum_size = Vector2(0, 140)
	L2.text = "[wave amp=3]a waving Control scene: ~test_card and the tag moves it too.]"
	L2.play_intro()
	box.add_child(L2)

	var L3 := RichLabel.new()
	L3.font_size = 30
	L3.custom_minimum_size = Vector2(0, 140)
	L3.text = "[glow]the same card with [tint cyan]color tags] applied to the scene.] ~test_card"
	L3.play_intro()
	box.add_child(L3)
