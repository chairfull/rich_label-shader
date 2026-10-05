extends Control
## Demo: pooled damage numbers. Click to spawn a burst at the cursor.
## All numbers share one compiled shader (same tags); the pool avoids
## free/instantiate churn. Watch the counter — spawning is ~0.05 ms/label.

const POOL_SIZE := 24

var _pool: Array[RichLabel] = []
var _next := 0
var _count := 0
var _counter: Label

func _ready() -> void:
	# Don't swallow clicks: we want them in _unhandled_input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	for i in POOL_SIZE:
		var L := RichLabel.new()
		L.font_size = 34
		L.visible = false
		add_child(L)
		_pool.append(L)
	# Warm the shader cache once so bursts never hitch on compile.
	# (stays invisible; the shader compiles on text set, not on draw)
	_pool[0].text = "[rise][fade]-0]"

	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 18)
	_counter.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_counter.position = Vector2(20, 16)
	add_child(_counter)
	_update_counter()

	var hint := Label.new()
	hint.text = "click: damage burst"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	hint.position = Vector2(20, 44)
	add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_burst(get_global_mouse_position())
			get_viewport().set_input_as_handled()

func _burst(at: Vector2) -> void:
	for k in 6:
		var L := _pool[_next]
		_next = (_next + 1) % POOL_SIZE
		_count += 1
		var dmg := randi_range(7, 999)
		var crit := dmg > 700
		L.text = ("[rainbow]" if crit else "") + "[rise][fade]-%d]" % dmg
		L.position = at + Vector2(randf_range(-30, 30), randf_range(-16, 16))
		L.size = Vector2(160, 50)
		L.visible = true
		# Retrigger: new text rebuilds, intro tween restarts.
		L.play_intro()
	_update_counter()

func _update_counter() -> void:
	_counter.text = "spawned: %d  (pool %d, one shared shader)" % [_count, POOL_SIZE]
