extends SceneTree
## Benchmark: RichLabel vs built-in RichTextLabel.
## Run with rendering (Xvfb or a real GPU) for meaningful numbers:
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://addons/rich_label/tests/benchmark.gd
##
## Measures creation time (cold vs warm shader cache) and static render cost
## for N labels. llvmpipe numbers are relative — compare the deltas, and
## expect much lower absolute numbers on a real GPU.

const RL = preload("res://addons/rich_label/rich_label.gd")
const N := 100
const FRAMES := 90

func _initialize() -> void:
	_run.call_deferred()

func _frame_ms(frames: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0 / frames

func _run() -> void:
	var win := root
	win.size = Vector2i(1600, 900)
	for i in 5:
		await process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	for i in 10:
		await process_frame

	print("=== RichLabel vs RichTextLabel (%d labels) ===" % N)
	var base := await _frame_ms(FRAMES)

	# RichLabel cold.
	var t0 := Time.get_ticks_usec()
	var rls: Array = []
	for i in N:
		var L = RL.new()
		L.text = "[rise][fade]-%d]" % (10 + i)
		L.position = Vector2(50 + (i % 20) * 75, 50 + (i / 20) * 160)
		L.size = Vector2(70, 50)
		L.font_size = 28
		L.head = ""
		win.add_child(L)
		rls.append(L)
	var cold_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var rl_ms := await _frame_ms(FRAMES)

	# RichLabel warm (same tags → shader cache hit).
	t0 = Time.get_ticks_usec()
	for i in N:
		var L = RL.new()
		L.text = "[rise][fade]-%d]" % (1000 + i)
		L.position = Vector2(50 + (i % 20) * 75, 50 + (i / 20) * 160)
		L.size = Vector2(70, 50)
		L.font_size = 28
		L.head = ""
		win.add_child(L)
		rls.append(L)
	var warm_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw

	for L in rls:
		(L as Node).queue_free()
	for i in 10:
		await process_frame

	# RichTextLabel.
	t0 = Time.get_ticks_usec()
	var rtls: Array = []
	for i in N:
		var R := RichTextLabel.new()
		R.bbcode_enabled = true
		R.text = "-%d" % (10 + i)
		R.position = Vector2(50 + (i % 20) * 75, 50 + (i / 20) * 160)
		R.size = Vector2(70, 50)
		R.add_theme_font_size_override("normal_font_size", 28)
		win.add_child(R)
		rtls.append(R)
	var rtl_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var rtl_frame := await _frame_ms(FRAMES)

	print("creation:")
	print("  RichLabel cold (compile): %.1f ms (%.2f ms/label)" % [cold_ms, cold_ms / N])
	print("  RichLabel warm (cached):  %.1f ms (%.2f ms/label)" % [warm_ms, warm_ms / N])
	print("  RichTextLabel:             %.1f ms (%.2f ms/label)" % [rtl_ms, rtl_ms / N])
	print("render (%.1f ms baseline):" % base)
	print("  RichLabel x%d:    +%.1f ms (%.3f ms/label)" % [N, rl_ms - base, (rl_ms - base) / N])
	print("  RichTextLabel x%d: +%.1f ms (%.3f ms/label)" % [N, rtl_frame - base, (rtl_frame - base) / N])
	print("=== DONE ===")
	quit()
