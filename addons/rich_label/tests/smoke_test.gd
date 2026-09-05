extends SceneTree
## Headless smoke test for RichLabel: exercises the parser, layout, shaping,
## shader generation (incl. dilation + fx clock), batching and the reveal API.
## Run with:
##   godot --headless --path . -s res://addons/rich_label/tests/smoke_test.gd

var _fails: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	RTUtils.clear_cache()
	var label := RichLabel.new()
	root.add_child(label)

	var cases: Array[String] = [
		"plain text",
		"[fade]hello]",
		"[wave amp=2 freq=3]surfing]",
		"[pop][skew][tumble]geometry]]",
		"[rainbow speed=2]prism]",
		"[shake][sin][scatter][rise dir=90]chaos]]]]",
		"[sin]solo wave]",
		"[outline 3 black][shadow 2 2][glow]styled]]",
		"[outline 2 white]dilated only]",
		"[outline]bare inherits default size]",
		"[red][24]big red]",
		"[b]bold and [i]italic too]]",
		"=bold= and _slanted_",
		"[fade]unclosed span to eof",
		"escaped \\[tag\\] stays literal",
		"~test_icon inline",
		"~test_box scene",
		"~test_icon h=32 fit=none valign=top tail",
		"[wave]~test_icon ripple]",
		"[=mylink]click me]",
		"matrix[2] stays literal",
	]
	for i in cases.size():
		label.text = cases[i]
		await process_frame
		await process_frame
		var mat := label.material as ShaderMaterial
		if mat == null or mat.shader == null or mat.shader.code.is_empty():
			_fail("case %d '%s': no generated shader" % [i, cases[i]])
			continue
		var code := mat.shader.code
		var err := _balance_error(code)
		if err != "":
			_fail("case %d '%s': shader %s" % [i, cases[i], err])
		# Identity must travel via the vertex-stage varying; fragment COLOR is
		# pre-multiplied by the texture sample (breaks MSDF fonts).
		if "COLOR.r *" in code:
			_fail("case %d: fragment decodes identity from pre-multiplied COLOR" % i)
		if "varying vec2 rl_xfer;" not in code \
				or "rl_xfer = vec2(clamp(COLOR.r" not in code:
			_fail("case %d: identity varying not emitted" % i)
		if "~test_" in cases[i] and "instance uniform bool" not in code:
			_fail("case %d: inline item did not emit instance uniforms" % i)
		if "[wave" in cases[i]:
			if "glyph_origin_arr" not in code:
				_fail("case %d: vertex tag did not emit geometry arrays" % i)
			if "fx_time" not in code:
				_fail("case %d: fx_time uniform missing for TIME-using tag" % i)
			if _has_raw_time_token(code):
				_fail("case %d: raw engine TIME survived rewrite" % i)
		if "[outline" in cases[i] and "layer_radius_arr" not in code:
			_fail("case %d: dilation uniform missing for outline/glow" % i)
		# Any fx_time reference must have its uniform declared.
		if "fx_time" in code and "uniform float fx_time" not in code:
			_fail("case %d: fx_time referenced but never declared" % i)
		if "[shadow" in cases[i] and "[outline" not in cases[i] \
				and "layer_radius_arr" in code and "[glow]" not in cases[i]:
			_fail("case %d: shadow alone triggered dilation" % i)
		# Layer stride must equal the glyph count so layer*stride+glyph matches
		# the CPU upload layout exactly.
		if "[outline" in cases[i] or "[shadow" in cases[i]:
			var stride := _extract_layer_stride(code)
			if stride != -1 and stride != label._total_glyphs:
				_fail("case %d: layer stride %d != glyph count %d" % [i, stride, label._total_glyphs])

	_check_parser()
	_check_layout(label)
	await _check_default_outline(label)
	await _check_reveal_api(label)
	_check_batching(label)

	root.remove_child(label)
	label.free()
	RichLabel._shader_cache.clear()

	if _fails.is_empty():
		print("SMOKE OK")
		quit(0)
	else:
		for f in _fails:
			printerr("FAIL: " + f)
		quit(1)

func _fail(msg: String) -> void:
	_fails.append(msg)

func _has_raw_time_token(code: String) -> bool:
	var re := RegEx.create_from_string("\\bTIME\\b")
	return re.search(code) != null

func _extract_layer_stride(code: String) -> int:
	var re := RegEx.create_from_string("layer \\*(\\d+)\\+ glyph|layer \\* (\\d+) \\+ glyph")
	var m := re.search(code)
	if m == null:
		return -1
	return int(m.get_string(1)) if m.get_string(1) != "" else int(m.get_string(2))

## Catches syntax slips in generated GLSL (e.g. unbalanced parens).
func _balance_error(code: String) -> String:
	var stack: Array[String] = []
	var pairs := {")": "(", "}": "{", "]": "["}
	var in_str := false
	for i in code.length():
		var c := code[i]
		if c == "\"":
			in_str = not in_str
		elif not in_str:
			if c in "({[":
				stack.append(c)
			elif c in ")}]":
				if stack.is_empty() or stack[stack.size() - 1] != pairs[c]:
					return "unbalanced '%s' @%d" % [c, i]
				stack.pop_back()
	if not stack.is_empty():
		return "unclosed '%s'" % stack[stack.size() - 1]
	return ""

func _check_parser() -> void:
	var st := RichParser.ParsedStyle.new()
	st.color = Color.WHITE
	st.effect_strength = 1.0
	st.effect_speed = 1.0

	# Bare-word arg/kwarg values survive parsing.
	var segs := RichParser.parse_text("[outline 3 black]hi]", st, null)
	var segs_kw := RichParser.parse_text("[outline size=3 color=black]hi]", st, null)
	var ok_color := false
	for s in segs:
		for t in s.style.tags:
			if t.name == &"outline" and t.args.size() >= 2 \
					and int(t.args[0]) == 3 and String(t.args[1]) == "black":
				ok_color = true
	if not ok_color:
		_fail("parser: bare-word positional 'black' lost")
	ok_color = false
	for s in segs_kw:
		for t in s.style.tags:
			if t.name == &"outline" and String(t.kwargs.get("color", "")) == "black":
				ok_color = true
	if not ok_color:
		_fail("parser: bare-word kwarg 'black' lost")

	# Recognized unclosed span auto-closes at EOF.
	segs = RichParser.parse_text("[fade]never closed", st, null)
	var has_fade := false
	for s in segs:
		for t in s.style.tags:
			if t.name == &"fade":
				has_fade = true
	if not has_fade:
		_fail("parser: unclosed known span dropped its directive")

	# Unknown unclosed span degrades to literals.
	var joined := ""
	segs = RichParser.parse_text("[nosuchdirective]x", st, null)
	for s in segs:
		joined += s.text
	if joined != "[nosuchdirective]x":
		_fail("parser: unknown span not literal -> '%s'" % joined)

	# Escapes.
	joined = ""
	segs = RichParser.parse_text("\\[nope\\]", st, null)
	for s in segs:
		joined += s.text
	if joined != "[nope]":
		_fail("parser: escape failed -> '%s'" % joined)

	# Asset attributes.
	segs = RichParser.parse_text("~test_icon h=32 fit=none x", st, null)
	var attrs_ok := segs.size() == 1 \
		and int(segs[0].attrs.get("h", 0)) == 32 \
		and String(segs[0].attrs.get("fit", "")) == "none"
	if not attrs_ok:
		_fail("parser: asset attributes mis-parsed")

func _check_layout(label: RichLabel) -> void:
	label.autowrap = true
	label.size = Vector2(80, 200)
	await process_frame
	label.text = "the quick brown fox jumps over the lazy dog again and again"
	await process_frame
	await process_frame

	var lines_text := {}
	for it in label._items:
		if it is RichLabel.Glyph:
			lines_text[it.line_index] = String(lines_text.get(it.line_index, "")) + (it as RichLabel.Glyph).character
		if it.position.x < -0.5 or it.position.x > label.size.x + 0.5:
			_fail("layout: glyph outside wrap width (x=%f)" % it.position.x)
			break

	var fox_found := false
	for li in lines_text:
		if "fox" in lines_text[li]:
			fox_found = true
	if lines_text.is_empty() or not fox_found:
		_fail("layout: word 'fox' missing or split across lines")

	# Shaping: advances should be populated (or fall back cleanly) and positive.
	var shaped_any := false
	for it in label._items:
		if it is RichLabel.Glyph:
			var g := it as RichLabel.Glyph
			if g.advance_override >= 0.0:
				shaped_any = true
				break
	if not shaped_any:
		_fail("shaping: no shaped advances produced")

func _check_default_outline(label: RichLabel) -> void:
	# Default outline/glow settings now live on the tag instances; labels no
	# longer hold their own outline_default_*/glow_default_* exports.
	var o := label._default_outline
	var g := label._default_glow
	label.text = "[red]red [blue]blue]"
	o.set(&"mode", o.Mode.NONE)
	g.set(&"mode", g.Mode.NONE)
	label.rebuild()

	# COLOR mode: every non-space glyph gains an outline layer in the exact
	# configured color.
	o.set(&"mode", o.Mode.COLOR)
	o.set(&"outline_color", Color.PURPLE)
	label.rebuild()
	await process_frame
	await process_frame
	var checked := 0
	for it in label._items:
		if it is RichLabel.Glyph and (it as RichLabel.Glyph).character != " ":
			var gl := it as RichLabel.Glyph
			if gl.layer_count < 2 or gl.layer_colors.size() < 2 \
					or gl.layer_colors[1] != Color.PURPLE:
				_fail("default outline COLOR mode: wrong layers/colors on '%s'" % gl.character)
				return
			checked += 1
			break
	if checked == 0:
		_fail("default outline COLOR mode: no glyph to check")

	# SHIFTED mode: red fill must produce a darker red outline (same-ish hue).
	o.set(&"mode", o.Mode.SHIFTED)
	o.set(&"hue_shift", 0.0)
	label.rebuild()
	await process_frame
	await process_frame
	for it in label._items:
		if it is RichLabel.Glyph and (it as RichLabel.Glyph).character == "r":
			var gl := it as RichLabel.Glyph
			var oc := gl.layer_colors[1]
			var fh := RTUtils.rgb_to_hsv(gl.fill_color)
			var oh := RTUtils.rgb_to_hsv(oc)
			if gl.layer_count < 2:
				_fail("default outline SHIFTED mode: no layer added")
			elif absf(fh.x - oh.x) > 0.02 or oh.z >= fh.z:
				_fail("default outline SHIFTED mode: not darkened same-hue (fill=%s out=%s)" % [gl.fill_color, oc])
			break

	# Value slider extreme: -1.0 must yield a pure white outline.
	o.set(&"value", -1.0)
	label.rebuild()
	await process_frame
	await process_frame
	for it in label._items:
		if it is RichLabel.Glyph and (it as RichLabel.Glyph).character == "r":
			var oc_white := (it as RichLabel.Glyph).layer_colors[1]
			if not oc_white.is_equal_approx(Color(1, 1, 1, 1)):
				_fail("default outline value=-1: expected white, got %s" % oc_white)
			break
	o.set(&"value", 0.55)

	o.set(&"mode", o.Mode.NONE)
	label.rebuild()
	await process_frame
	await process_frame

	# Default glow COLOR mode: gains a trailing glow layer in the configured
	# color (alpha = intensity).
	label.text = "[red]red"
	g.set(&"mode", g.Mode.COLOR)
	g.set(&"glow_color", Color(0.2, 0.8, 1.0))
	label.rebuild()
	await process_frame
	await process_frame
	for it in label._items:
		if it is RichLabel.Glyph and (it as RichLabel.Glyph).character == "r":
			var gg := it as RichLabel.Glyph
			var want := Color(0.2, 0.8, 1.0, 0.8)
			if gg.layer_count < 2 or not gg.layer_colors[gg.layer_count - 1].is_equal_approx(want):
				_fail("default glow COLOR mode: expected %s got %s" % [want, gg.layer_colors])
			break

	# SHIFTED glow toward white: -0.9 lerps red fill to (1, 0.9, 0.9).
	g.set(&"mode", g.Mode.SHIFTED)
	g.set(&"value", -0.9)
	label.rebuild()
	await process_frame
	await process_frame
	for it in label._items:
		if it is RichLabel.Glyph and (it as RichLabel.Glyph).character == "r":
			var gg2 := it as RichLabel.Glyph
			var wantw := Color(1.0, 0.9, 0.9, 0.8)
			if gg2.layer_count < 2 or not gg2.layer_colors[gg2.layer_count - 1].is_equal_approx(wantw):
				_fail("default glow SHIFTED value=-0.9: expected %s got %s" % [wantw, gg2.layer_colors])
			break
	g.set(&"mode", g.Mode.NONE)
	label.rebuild()
	await process_frame

func _check_reveal_api(label: RichLabel) -> void:
	label.autowrap = false
	label.pause_on_punctuation = true
	label.text = "Wait. Then go! Fast..."
	await process_frame

	# seek()
	label.seek(-0.5)
	if absf(label.progress - (-0.5)) > 0.0001:
		_fail("reveal: seek(-0.5) -> progress=%f" % label.progress)

	# loop tick advances progress without a tween.
	label.loop_mode = RichLabel.LoopMode.LOOP
	label.seek(-1.0)
	label._loop_tick(0.5)
	if label.progress <= -1.0:
		_fail("reveal: LOOP tick did not advance progress")
	label.loop_mode = RichLabel.LoopMode.NONE

	# finished signal fires after an intro tween completes.
	label.punctuation_pause = 0.05
	label.newline_pause = 0.05
	var done := [false]
	label.intro_finished.connect(func(): done[0] = true)
	label.play_intro()
	var deadline := Time.get_ticks_msec() + 8000
	while not done[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	if not done[0]:
		_fail("reveal: intro_finished never fired (progress=%f)" % label.progress)

func _check_batching(label: RichLabel) -> void:
	label.text = "batched glyphs"
	label.use_batched_mesh = true
	await process_frame
	await process_frame
	if label._batch_surfaces.is_empty():
		_fail("batching: no mesh surfaces built")
	else:
		var verts := 0
		for s in label._batch_surfaces:
			var m := s.mesh as ArrayMesh
			var arrs := m.surface_get_arrays(0)
			var va := arrs[Mesh.ARRAY_VERTEX] as PackedVector2Array
			verts += va.size()
			# UVs must be normalized sampler coords; raw atlas pixels render nothing.
			for uv in arrs[Mesh.ARRAY_TEX_UV] as PackedVector2Array:
				if uv.x < -0.001 or uv.x > 1.001 or uv.y < -0.001 or uv.y > 1.001:
					_fail("batching: UV out of 0..1 range (%f, %f)" % [uv.x, uv.y])
					break
		if verts == 0:
			_fail("batching: surface has no vertices")

	label.use_batched_mesh = false
	await process_frame
	if not label._batch_surfaces.is_empty():
		_fail("batching: surfaces not released when disabled")
	label.use_batched_mesh = true
