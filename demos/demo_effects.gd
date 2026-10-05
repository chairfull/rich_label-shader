extends Control
## Demo: effect gallery with live param sliders, global speed, and replay.
## Layout: sliders stacked on the left, preview text on the right.
## All animation is shader-side; sliders just rebuild the tag markup.

var _rows: Array = [
	{"tag": "wave", "sample": "wave: the classic",
		"params": [["amp", 4.0, 0.0, 12.0], ["freq", 1.5, 0.0, 6.0]]},
	{"tag": "rainbow", "sample": "rainbow: fragment color cycle",
		"params": [["speed", 1.0, 0.0, 4.0], ["saturation", 1.0, 0.0, 1.0]]},
	{"tag": "shake", "sample": "shake: jittery",
		"params": [["amp", 3.0, 0.0, 10.0], ["freq", 24.0, 0.0, 60.0]]},
	{"tag": "blur", "sample": "blur reveal: soft typewriter", "head": true,
		"params": [["radius", 8.0, 0.0, 20.0]]},
	{"tag": "shred", "sample": "shred reveal: torn typewriter", "head": true,
		"params": [["distance", 28.0, 0.0, 60.0]]},
]

var _labels: Array[RichLabel] = []
var _param_vals: Array = []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 40
	scroll.offset_right = -40
	scroll.offset_top = 24
	scroll.offset_bottom = -100
	add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 18)
	scroll.add_child(box)

	var title := RichLabel.new()
	title.text = "effect gallery"
	title.font_size = 40
	box.add_child(title)

	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var vals := {}
		for pv in row["params"]:
			vals[pv[0]] = pv[1]
		_param_vals.append(vals)

		# Row: sliders (left, vertical) | preview (right).
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 30)
		box.add_child(h)

		var sliders := VBoxContainer.new()
		sliders.custom_minimum_size = Vector2(300, 0)
		sliders.add_theme_constant_override("separation", 6)
		h.add_child(sliders)

		var name_lab := Label.new()
		name_lab.text = row["tag"]
		name_lab.add_theme_font_size_override("font_size", 20)
		name_lab.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
		sliders.add_child(name_lab)

		for pv in row["params"]:
			sliders.add_child(_make_slider(i, pv[0], pv[1], pv[2], pv[3]))

		var preview := RichLabel.new()
		preview.font_size = 32
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(preview)
		_labels.append(preview)
		_refresh_row(i)

		var sep := HSeparator.new()
		box.add_child(sep)

	# Bottom bar: global speed + replay.
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 60
	bar.offset_right = -60
	bar.offset_top = -80
	bar.offset_bottom = -24
	bar.add_theme_constant_override("separation", 16)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bar)

	var speed_lab := Label.new()
	speed_lab.text = "effect speed"
	speed_lab.add_theme_font_size_override("font_size", 18)
	bar.add_child(speed_lab)

	var speed := HSlider.new()
	speed.min_value = 0.1
	speed.max_value = 3.0
	speed.step = 0.05
	speed.value = 1.0
	speed.custom_minimum_size = Vector2(220, 0)
	speed.value_changed.connect(_on_speed)
	bar.add_child(speed)

	var replay := Button.new()
	replay.text = "replay"
	replay.pressed.connect(_on_replay)
	bar.add_child(replay)

func _make_slider(row_i: int, pname: String, val: float, lo: float, hi: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(110, 0)
	lab.add_theme_font_size_override("font_size", 15)
	lab.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	h.add_child(lab)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.1 if hi - lo > 2.0 else 0.01
	sl.value = val
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(_on_param.bind(row_i, pname, lab))
	h.add_child(sl)
	_update_param_label(lab, pname, val)
	return h

func _update_param_label(lab: Label, pname: String, val: float) -> void:
	lab.text = "%s %.1f" % [pname, val]

func _on_param(val: float, row_i: int, pname: String, lab: Label) -> void:
	_param_vals[row_i][pname] = val
	_update_param_label(lab, pname, val)
	_refresh_row(row_i)

func _refresh_row(i: int) -> void:
	var row: Dictionary = _rows[i]
	var parts: PackedStringArray = []
	for pv in row["params"]:
		parts.append("%s=%s" % [pv[0], _fmt(_param_vals[i][pv[0]])])
	var tag := "%s %s" % [row["tag"], " ".join(parts)]
	if row.get("head", false):
		_labels[i].head = tag
		_labels[i].text = row["sample"]
	else:
		_labels[i].head = ""
		_labels[i].text = "[%s]%s]" % [tag, row["sample"]]
	_labels[i].play_intro()

func _fmt(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

func _on_speed(val: float) -> void:
	for L in _labels:
		L.time_scale = val

func _on_replay() -> void:
	for L in _labels:
		L.play_intro()
