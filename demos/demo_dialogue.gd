extends Control
## Demo: RPG dialogue box with typewriter reveal.
## Click (or Space) to complete the current line, then advance.
## Uses the [blur] reveal head for a soft typewriter.

var _lines: Array[String] = [
	"[blur radius=6]Stranger, you walk a dangerous road. Turn back while you still can.]",
	"[blur radius=6]The [red]crimson woods] are [wave amp=2]restless] tonight...",
	"[blur radius=6]Take this [u]charm]. It will [rainbow]protect] you when words fail.]",
]
var _idx := 0
var _label: RichLabel
var _hint: Label

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -220
	panel.offset_left = 60
	panel.offset_right = -60
	panel.offset_bottom = -40
	add_child(panel)

	_label = RichLabel.new()
	_label.custom_minimum_size = Vector2(0, 140)
	_label.font_size = 30
	_label.head = "blur"
	panel.add_child(_label)

	_hint = Label.new()
	_hint.text = "click / space: complete → advance"
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -30
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	_show_line()

func _show_line() -> void:
	_label.text = _lines[_idx]
	_label.play_intro()

func _unhandled_input(event: InputEvent) -> void:
	var advance := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		advance = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event.is_action_pressed("ui_accept"):
		advance = true
	if not advance:
		return
	get_viewport().set_input_as_handled()
	# Standard RPG loop: if revealing, complete; else next line.
	if _label.progress < 0.0:
		_label.seek(0.0)
	else:
		_idx = (_idx + 1) % _lines.size()
		_show_line()
