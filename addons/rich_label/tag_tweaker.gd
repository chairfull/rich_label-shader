@tool
extends Control
## Editor dock: tag tweaker. Scans all RichTag scripts, lets you tweak
## params with sliders, previews live, and copies the markup to clipboard.

var _tag_list: ItemList
var _param_box: VBoxContainer
var _preview: RichLabel
var _markup_label: Label
var _tags: Array = []  # [{name, script, instance, params: [{name, type, hint, min, max, step, value}]}]
var _selected := -1

func _ready() -> void:
	custom_minimum_size = Vector2(380, 400)
	_scan_tags()
	_build_ui()
	if not _tags.is_empty():
		_tag_list.select(0)
		_on_tag_selected(0)

func _scan_tags() -> void:
	var dir := DirAccess.open("res://addons/rich_label/rl_tags")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".gd") or f.ends_with(".uid"):
			continue
		var path := "res://addons/rich_label/rl_tags/" + f
		var scr: Script = load(path)
		if scr == null:
			continue
		var inst: RichTag = scr.new()
		if not (inst is RichTag):
			continue
		var tag_name := f.get_basename()
		var params := []
		for p in inst.get_property_list():
			if not (p.usage & PROPERTY_USAGE_EDITOR):
				continue
			if p.name in ["effect_strength", "effect_speed"]:
				continue  # global multipliers, not per-tag settings
			params.append({
				"name": p.name,
				"type": p.type,
				"hint": p.hint,
				"hint_string": p.hint_string,
				"value": inst.get(p.name),
			})
		_tags.append({"name": tag_name, "instance": inst, "params": params})
	_tags.sort_custom(func(a, b): return a.name < b.name)

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	_tag_list = ItemList.new()
	_tag_list.custom_minimum_size = Vector2(120, 0)
	_tag_list.item_selected.connect(_on_tag_selected)
	split.add_child(_tag_list)
	for t in _tags:
		_tag_list.add_item(t.name)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	_preview = RichLabel.new()
	_preview.custom_minimum_size = Vector2(0, 80)
	_preview.font_size = 28
	right.add_child(_preview)

	_param_box = VBoxContainer.new()
	_param_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_param_box)

	_markup_label = Label.new()
	_markup_label.add_theme_font_size_override("font_size", 13)
	_markup_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_markup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_markup_label)

	var copy_btn := Button.new()
	copy_btn.text = "copy markup"
	copy_btn.pressed.connect(_on_copy)
	right.add_child(copy_btn)

func _on_tag_selected(idx: int) -> void:
	_selected = idx
	for c in _param_box.get_children():
		c.queue_free()
	var tag: Dictionary = _tags[idx]
	for pm in tag.params:
		_param_box.add_child(_make_param_row(tag, pm))
	_refresh()

func _make_param_row(tag: Dictionary, pm: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(90, 0)
	lab.add_theme_font_size_override("font_size", 13)
	h.add_child(lab)

	var val = pm.value
	if pm.type == TYPE_BOOL:
		var chk := CheckBox.new()
		chk.button_pressed = val
		chk.toggled.connect(func(v): _on_param_bool(tag, pm, v, lab))
		h.add_child(chk)
	elif pm.type == TYPE_INT and pm.hint == PROPERTY_HINT_ENUM:
		var opt := OptionButton.new()
		var names: PackedStringArray = pm.hint_string.split(",")
		for n in names:
			opt.add_item(n.get_slice(":", 0))
		opt.selected = val
		opt.item_selected.connect(func(i): _on_param_int(tag, pm, i, lab))
		h.add_child(opt)
	elif pm.type == TYPE_FLOAT or pm.type == TYPE_INT:
		var sl := HSlider.new()
		var lo := 0.0
		var hi := 10.0
		var step := 0.1
		if pm.hint == PROPERTY_HINT_RANGE:
			var parts: PackedStringArray = pm.hint_string.split(",")
			if parts.size() > 0:
				lo = float(parts[0])
			if parts.size() > 1:
				hi = float(parts[1])
			if parts.size() > 2:
				step = float(parts[2])
		sl.min_value = lo
		sl.max_value = hi
		sl.step = step
		sl.value = val
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(func(v): _on_param_float(tag, pm, v, lab))
		h.add_child(sl)
	elif pm.type == TYPE_COLOR:
		var cp := ColorPickerButton.new()
		cp.color = val
		cp.color_changed.connect(func(c): _on_param_color(tag, pm, c, lab))
		h.add_child(cp)
	else:
		var le := LineEdit.new()
		le.text = str(val)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_submitted.connect(func(t): _on_param_text(tag, pm, t, lab))
		h.add_child(le)
	_update_param_label(lab, pm.name, val)
	return h

func _update_param_label(lab: Label, pname: String, val) -> void:
	if val is float:
		lab.text = "%s %.2f" % [pname, val]
	else:
		lab.text = "%s %s" % [pname, str(val)]

func _on_param_float(tag: Dictionary, pm: Dictionary, v: float, lab: Label) -> void:
	pm.value = v
	tag.instance.set(pm.name, v)
	_update_param_label(lab, pm.name, v)
	_refresh()

func _on_param_int(tag: Dictionary, pm: Dictionary, v: int, lab: Label) -> void:
	pm.value = v
	tag.instance.set(pm.name, v)
	_update_param_label(lab, pm.name, v)
	_refresh()

func _on_param_bool(tag: Dictionary, pm: Dictionary, v: bool, lab: Label) -> void:
	pm.value = v
	tag.instance.set(pm.name, v)
	_update_param_label(lab, pm.name, v)
	_refresh()

func _on_param_color(tag: Dictionary, pm: Dictionary, v: Color, lab: Label) -> void:
	pm.value = v
	tag.instance.set(pm.name, v)
	_update_param_label(lab, pm.name, v)
	_refresh()

func _on_param_text(tag: Dictionary, pm: Dictionary, v: String, lab: Label) -> void:
	pm.value = v
	tag.instance.set(pm.name, v)
	_update_param_label(lab, pm.name, v)
	_refresh()

func _build_markup() -> String:
	if _selected < 0:
		return ""
	var tag: Dictionary = _tags[_selected]
	var parts: PackedStringArray = []
	for pm in tag.params:
		var v = pm.value
		var def = tag.instance.get(pm.name)  # current (tweaked) value
		# Only include non-default? Simpler: include all.
		if v is float:
			parts.append("%s=%s" % [pm.name, _fmt(v)])
		elif v is Color:
			parts.append("%s=#%s" % [pm.name, v.to_html()])
		else:
			parts.append("%s=%s" % [pm.name, str(v)])
	var tag_str: String = tag.name
	if not parts.is_empty():
		tag_str += " " + " ".join(parts)
	return "[%s]preview]" % tag_str

func _fmt(v: float) -> String:
	var s := "%.3f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

func _refresh() -> void:
	var markup := _build_markup()
	_markup_label.text = markup
	_preview.text = markup
	_preview.play_intro()

func _on_copy() -> void:
	DisplayServer.clipboard_set(_build_markup())
