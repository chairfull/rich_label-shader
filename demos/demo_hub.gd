extends Control
## Meta demo: hub with arrows and a dropdown to swap between demos.

var _demos: Array = [
	["dialogue", "res://demos/demo_dialogue.tscn"],
	["effects", "res://demos/demo_effects.tscn"],
	["damage numbers", "res://demos/demo_damage_numbers.tscn"],
	["inline", "res://demos/demo_inline.tscn"],
]
var _idx := 0
var _holder: Control
var _dropdown: OptionButton

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_holder = Control.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holder.offset_top = 60
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)

	# Nav bar: < [dropdown] >
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 20
	bar.offset_top = 12
	bar.offset_right = -20
	bar.offset_bottom = 52
	bar.add_theme_constant_override("separation", 10)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bar)

	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(48, 0)
	prev.pressed.connect(func(): _select((_idx - 1 + _demos.size()) % _demos.size()))
	bar.add_child(prev)

	_dropdown = OptionButton.new()
	_dropdown.custom_minimum_size = Vector2(220, 0)
	for d in _demos:
		_dropdown.add_item(d[0])
	_dropdown.item_selected.connect(_on_dropdown)
	bar.add_child(_dropdown)

	var next := Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(48, 0)
	next.pressed.connect(func(): _select((_idx + 1) % _demos.size()))
	bar.add_child(next)

	_select(0)

func _select(i: int) -> void:
	_idx = i
	_dropdown.selected = i
	for c in _holder.get_children():
		c.queue_free()
	var ps: PackedScene = load(_demos[i][1])
	var inst = ps.instantiate()
	# The demo roots are full-rect Controls; shift content below the nav bar.
	# (Demos already use their own top offsets, so just add directly.)
	_holder.add_child(inst)

func _on_dropdown(i: int) -> void:
	_select(i)
