@tool
class_name RichLabel
extends Control

## Emitted when [=link]s are interacted with.
signal clicked(url: Variant)
signal alt_clicked(url: Variant)
signal hovered(url: Variant)
signal unhovered(url: Variant)

## Emitted when an intro reveal finishes playing.
signal intro_finished
## Emitted when an outro reveal finishes playing.
signal outro_finished

## Called on Objects when used w the [=link] pattern.
const FUNC_LINK_HOVERED := &"_rich_label_hovered"
const FUNC_LINK_UNHOVERED := &"_rich_label_unhovered"
const FUNC_LINK_CLICKED := &"_rich_label_clicked"
const FUNC_LINK_ALT_CLICKED := &"_rich_label_alt_clicked"
const FUNC_GET_TOOLTIP := &"get_tooltip_text"

const _FONT_VARIATION_MAP := {
	"variation_embolden": "variation_embolden",
	"embolden": "variation_embolden",
	"weight": "variation_weight",
	"variation_weight": "variation_weight",
	"slant": "variation_slant",
}

const _PUNCTUATION := ".,!?;:)]}>/\\\"'"
const MAX_LINKS := 32
## Compiled Shader reuse across rebuilds keyed by generated-code hash.
const SHADER_CACHE_MAX := 24
## Max pooled inline nodes kept per asset id between rebuilds.
const INLINE_POOL_LIMIT := 8
## Shear applied for faux italics (see RTUtils.FAUX_ITALIC_SLANT note).
const ITALIC_SLANT := RTUtils.FAUX_ITALIC_SLANT

enum StaggerMode {
	ALL,		## All characters fade in/out at same time.
	CHARACTER,	## Characters fade in/out one at a time.
	WORD,		## Words fade in/out once at a time.
	LINE,		## Lines fade in/out once at a time.
}

enum AlignMode {
	LEFT,
	CENTER,
	RIGHT,
	FILL,
}

enum ItemKind {
	LINE_BREAK,
	GLYPH,
	IMAGE,
	SCENE,
}

enum AutoplayMode {
	NONE,	## Nothing plays automatically.
	INTRO,	## Plays the intro when the node enters the tree.
	OUTRO,	## Plays the outro when the node enters the tree.
}

enum LoopMode {
	NONE,		## Reveals play once on demand.
	LOOP,		## Repeats the intro cycle forever.
	PING_PONG,	## Bounces between fully-hidden and fully-shown forever.
}

class LinkData extends Resource:
	var meta: Variant
	var index: int
	var state: float
	var rects: Array[Rect2]
	var tween: Tween

var _items: Array[LayoutItem]
var _total_glyphs := 0
var _total_words := 0
var _total_lines := 1
var _total_layers := 1
var _content_width := 0.0
var _content_height := 0.0
var _last_custom_minimum_size := Vector2(-1.0, -1.0)
var _link_data: Dictionary[int, LinkData]
var _hovered_link_index := -1
var _inline_pool: Dictionary[String, Array] = {}
var _inline_relayout_pending := false
var _fx_time := 0.0
var _uses_fx_clock := false
## Persistent default-tag instances carrying the outline/glow defaults. These
## are the single source of truth for the glyph-wide default effects; labels no
## longer hold their own outline/glow settings (that lives on the tags).
var _default_outline: RichTag = null
var _default_glow: RichTag = null
var _loop_phase := 0.0
var _batch_surfaces: Array[Dictionary] = []  ## { tex: Texture2D, mesh: ArrayMesh }
static var _shader_cache: Dictionary[int, Shader] = {}
static var _node_ref_re: RegEx
static var _time_token_re: RegEx

@export var head := "fade":
	set(value):
		if head != value:
			head = value
			rebuild()

@export_multiline() var text := "":
	set(value):
		if text != value:
			text = value
			rebuild()

@export var context: Node:
	set(value):
		if context != value:
			context = value
			rebuild()

@export var font: Font:
	set(value):
		if font != value:
			font = value
			rebuild()

@export_range(0, 128, 1, "or_greater") var font_size := 24:
	set(value):
		value = maxi(0, value)
		if font_size != value:
			font_size = value
			rebuild()

@export var color := Color.WHITE:
	set(value):
		if color != value:
			color = value
			rebuild()

## Default outline/glow behavior lives on the [outline] and [glow] tags
## (rl_tags/outline.gd, rl_tags/glow.gd); this label only keeps default-tag
## instances to drive the glyph-wide defaults.

@export_storage var progress: float:
	set(value):
		progress = clampf(value, -1.0, 1.0)
		_set_shader_param("progress", progress)
		if Engine.is_editor_hint():
			update_configuration_warnings()

var _tween: Tween

## Inspector play buttons (Godot 4.4+ tool buttons; no custom inspector needed).
@export_tool_button("Play Intro", "Animation") var anim_intro_play: Callable = play_intro
@export_tool_button("Play Outro", "Animation") var anim_outro_play: Callable = play_outro

func play_intro() -> void:
	_play_reveal(true)

func play_outro() -> void:
	_play_reveal(false)

func _play_reveal(intro: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_speed_scale(maxf(0.001, time_scale))
	_tween.finished.connect(_on_reveal_finished.bind(intro), CONNECT_ONE_SHOT)
	var duration := anim_intro_duration if intro else anim_outro_duration
	var trans := anim_intro_tween if intro else anim_outro_tween
	var ez := anim_intro_ease if intro else anim_outro_ease
	var mode := anim_intro_mode if intro else anim_outro_mode
	var stagger := anim_intro_stagger if intro else anim_outro_stagger
	var bps := _build_pause_breakpoints(mode, stagger, intro)
	var lo := -1.0 if intro else 0.0
	var hi := 0.0 if intro else 1.0
	if bps.is_empty():
		_tween.tween_property(self, "progress", hi, duration)\
			.from(lo)\
			.set_trans(trans)\
			.set_ease(ez)
		return
	var p_cur := lo
	for bp: Dictionary in bps:
		var p_next := clampf(float(bp.p), minf(lo, hi), maxf(lo, hi))
		if absf(p_next - p_cur) > 0.0001:
			_tween.tween_property(self, "progress", p_next, absf(p_next - p_cur) * duration).from(p_cur)
			p_cur = p_next
		_tween.tween_interval(float(bp.dur))
	if absf(hi - p_cur) > 0.0001:
		_tween.tween_property(self, "progress", hi, absf(hi - p_cur) * duration).from(p_cur)

func _on_reveal_finished(intro: bool) -> void:
	if intro:
		intro_finished.emit()
	else:
		outro_finished.emit()

@export_storage var anim_intro_mode := StaggerMode.CHARACTER:
	set(value):
		if anim_intro_mode != value:
			anim_intro_mode = value
			rebuild()

@export_storage var anim_intro_duration := 1.0
@export_storage var anim_intro_tween := Tween.TRANS_SINE
@export_storage var anim_intro_ease := Tween.EASE_IN_OUT
@export_storage var anim_intro_stagger := 0.5:
	set(value):
		value = clampf(value, 0.0, 0.98)
		if not is_equal_approx(anim_intro_stagger, value):
			anim_intro_stagger = value
			_set_shader_param("intro_stagger", anim_intro_stagger)

@export_storage var anim_outro_mode := StaggerMode.ALL:
	set(value):
		if anim_outro_mode != value:
			anim_outro_mode = value
			rebuild()

@export_storage var anim_outro_stagger := 0.5:
	set(value):
		value = clampf(value, 0.0, 0.98)
		if not is_equal_approx(anim_outro_stagger, value):
			anim_outro_stagger = value
			_set_shader_param("outro_stagger", anim_outro_stagger)

@export_storage var anim_outro_duration := 1.0
@export_storage var anim_outro_tween := Tween.TRANS_SINE
@export_storage var anim_outro_ease := Tween.EASE_IN_OUT

@export var pause_on_punctuation := true

@export_range(0.0, 3.0, 0.01) var punctuation_pause := 0.35

@export var pause_on_newline := true

@export_range(0.0, 3.0, 0.01) var newline_pause := 0.55

## Multiplies effect animation speed (shader fx_time) and reveal tween speeds.
@export_range(0.0, 8.0, 0.01) var time_scale := 1.0

## Starts a reveal automatically when the node enters the tree.
@export var autoplay := AutoplayMode.NONE

## Continuously drives progress without tweens.
@export var loop_mode := LoopMode.NONE

## Measure text with TextServer shaping (kerning-aware) instead of per-char sizing.
@export var shaping := true

## Draw glyphs as one batched mesh per font texture instead of draw_char calls.
@export_storage var use_batched_mesh := true:
	set(value):
		if use_batched_mesh != value:
			use_batched_mesh = value
			if not _items.is_empty():
				_build_batch_meshes()
				queue_redraw()

@export_storage var char_spacing := 0.0:
	set(value):
		if not is_equal_approx(char_spacing, value):
			char_spacing = value
			rebuild()

@export_storage var line_spacing := 0.0:
	set(value):
		if not is_equal_approx(line_spacing, value):
			line_spacing = value
			rebuild()

@export_storage var autowrap := false:
	set(value):
		if autowrap != value:
			autowrap = value
			rebuild()

@export_storage var horizontal_alignment := HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER:
	set(value):
		if horizontal_alignment != value:
			horizontal_alignment = value
			rebuild()

@export_storage var vertical_alignment := VerticalAlignment.VERTICAL_ALIGNMENT_CENTER:
	set(value):
		if vertical_alignment != value:
			vertical_alignment = value
			rebuild()

var _theme_font_cache: Font
var _theme_font_size_cache := -1

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for bucket in _inline_pool.values():
			for n: Node in bucket:
				if is_instance_valid(n):
					n.free()
		_inline_pool.clear()
	elif what == NOTIFICATION_RESIZED:
		if autowrap: rebuild()
	elif what == NOTIFICATION_THEME_CHANGED:
		# Theme-changed fires for many unrelated reasons; only rebuild when the
		# values we actually consume have changed.
		var tf := get_theme_default_font()
		var ts := get_theme_default_font_size()
		if tf != _theme_font_cache or ts != _theme_font_size_cache:
			_theme_font_cache = tf
			_theme_font_size_cache = ts
			rebuild()

func _set_shader_param(param: StringName, value: Variant) -> void:
	var sm := material as ShaderMaterial
	if sm:
		sm.set_shader_parameter(param, value)

func _ready() -> void:
	if _default_outline == null:
		var os := RTUtils.get_gd_script(&"outline")
		if os != null:
			_default_outline = os.new() as RichTag
	if _default_glow == null:
		var gs := RTUtils.get_gd_script(&"glow")
		if gs != null:
			_default_glow = gs.new() as RichTag
	match autoplay:
		AutoplayMode.INTRO:
			play_intro.call_deferred()
		AutoplayMode.OUTRO:
			play_outro.call_deferred()

func _process(delta: float) -> void:
	# Clamp per-frame contribution: editor stalls / alt-tab produce huge deltas
	# that would otherwise read as sudden jumps ("warps") in effect time.
	var scaled := minf(delta, 0.1) * time_scale
	if scaled > 0.0 and visible:
		if _uses_fx_clock and is_inside_tree():
			_fx_time += scaled
			_set_shader_param(&"fx_time", _fx_time)
		_loop_tick(scaled)

## Drives progress continuously for loop modes (tweens take precedence).
func _loop_tick(scaled_delta: float) -> void:
	if loop_mode == LoopMode.NONE or not is_inside_tree():
		return
	if _tween and _tween.is_running():
		_loop_phase = clampf((progress + 1.0) * 0.5, 0.0, 1.0)
		return
	match loop_mode:
		LoopMode.LOOP:
			_loop_phase = fposmod(_loop_phase + scaled_delta / maxf(0.05, anim_intro_duration), 1.0)
			progress = -1.0 + _loop_phase
		LoopMode.PING_PONG:
			_loop_phase = fposmod(_loop_phase + scaled_delta / maxf(0.05, anim_intro_duration + anim_outro_duration) * 0.5, 2.0)
			progress = -1.0 + (1.0 - absf(_loop_phase - 1.0)) * 2.0

## Jumps to an absolute reveal state: -1 fully hidden, 0 fully shown,
## 1 hidden again through the outro.
func seek(p: float) -> void:
	if _tween:
		_tween.kill()
	progress = clampf(p, -1.0, 1.0)

var _rebuilding := false

func rebuild() -> void:
	if _rebuilding: return
	_rebuilding = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuilding = false
	if Engine.is_editor_hint():
		RTUtils.clear_cache()
	_ensure_shader_material()
	_release_inline_nodes()

	var combined := ("[%s]%s]" % [head, text]) if head else text
	var default_style := RichParser.ParsedStyle.new()
	default_style.color = color
	default_style.effect_strength = 1.0
	default_style.effect_speed = 1.0
	var segments := RichParser.parse_text(combined, default_style, context)

	_segments_to_items(segments)
	_layout_items(_items)
	_apply_reveal_positions(_items)
	_build_link_data(_items)
	_update_shader()
	_sync_inline_nodes()
	_build_batch_meshes()
	queue_redraw()

func _build_link_data(items: Array[LayoutItem]) -> void:
	for t: LinkData in _link_data.values():
		if t.tween: t.tween.kill()
	_link_data.clear()
	var link_idx := 0
	var prev_meta: Variant = &"__NONE__"  # sentinel -- won't match null or any real meta
	for item in items:
		if item.link_meta == null:
			item.link_index = -1
			prev_meta = null
			continue
		# Start a new group whenever the meta transitions (new link span).
		if item.link_meta != prev_meta:
			var ld := LinkData.new()
			ld.index = link_idx
			ld.meta = item.link_meta
			_link_data[link_idx] = ld
			link_idx += 1
		item.link_index = link_idx - 1
		prev_meta = item.link_meta
		_link_data[link_idx - 1].rects.append(Rect2(item.position, item.size))
	# Rebuild invalidates any in-flight hover state.
	if _hovered_link_index != -1:
		_notify_link_hovered(_hovered_link_index, false)
	_hovered_link_index = -1
	mouse_default_cursor_shape = CURSOR_ARROW
	mouse_filter = MOUSE_FILTER_IGNORE if _link_data.is_empty() else MOUSE_FILTER_STOP

## Only the link rectangles are hittable — empty areas pass input through.
func _has_point(point: Vector2) -> bool:
	for ld in _link_data.values():
		for r in ld.rects:
			if r.has_point(point):
				return true
	return false

func _resolve_meta(meta: Variant) -> Variant:
	if meta == null:
		return null
	match typeof(meta):
		TYPE_INT:
			return instance_from_id(meta)
		TYPE_STRING:
			var s := meta as String
			if s.is_valid_int():
				return instance_from_id(s.to_int())
			# "Name:<Class#instance_id>"
			if _node_ref_re == null:
				_node_ref_re = RegEx.create_from_string("(\\w+):<([\\w\\d]+)#(\\d+)>")
			var rm_node := _node_ref_re.search(s)
			if rm_node:
				return instance_from_id(rm_node.get_string(3).to_int())
	return meta

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local_pos := (event as InputEventMouseMotion).position
		var found_link_index := -1
		for link_index in _link_data:
			for rect in _link_data[link_index].rects:
				if rect.has_point(local_pos):
					found_link_index = link_index
					break
			if found_link_index != -1:
				break
		
		if found_link_index != _hovered_link_index:
			if _hovered_link_index != -1:
				_animate_link_state(_hovered_link_index, 1.0) # Back to default
				_notify_link_hovered(_hovered_link_index, false)
			
			_hovered_link_index = found_link_index
			mouse_default_cursor_shape = CURSOR_POINTING_HAND if _hovered_link_index != -1 else CURSOR_ARROW
			
			if _hovered_link_index != -1:
				_animate_link_state(_hovered_link_index, 2.0) # To hovered
				_notify_link_hovered(_hovered_link_index, true)
				
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _hovered_link_index != -1 and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			var alt := mb.button_index == MOUSE_BUTTON_RIGHT
			var meta := _resolve_meta(_link_data[_hovered_link_index].meta)
			(alt_clicked if alt else clicked).emit(meta)
			RTUtils.try_call(meta, FUNC_LINK_ALT_CLICKED if alt else FUNC_LINK_CLICKED, null, self)

func _animate_link_state(link_index: int, target_state: float) -> void:
	if not link_index in _link_data:
		return
	
	var data := _link_data[link_index]
	
	if data.tween:
		data.tween.kill()
	
	data.tween = create_tween()
	
	data.tween.tween_method(
		func(v: float):
			data.state = v
			_update_link_shader_state(),
		data.state, target_state, 0.15
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _update_link_shader_state() -> void:
	var cap := mini(_link_data.size(), MAX_LINKS)
	var states := RTUtils.packedFloat32(maxi(1, cap), 1.0)
	for l in _link_data.values():
		if l.index < cap:
			states[l.index] = l.state
	_set_shader_param(&"link_states_arr", states)

func _notify_link_hovered(link_index: int, is_hovered: bool) -> void:
	if not _link_data.has(link_index): return
	var meta := _resolve_meta(_link_data[link_index].meta)
	if is_hovered:
		hovered.emit(meta)
		if meta is Object:
			var obj := meta as Object
			RTUtils.try_call(obj, FUNC_LINK_HOVERED, null, self)
			var tooltip: Variant = RTUtils.try_call(obj, FUNC_GET_TOOLTIP)
			if not tooltip and &"tooltip_text" in obj:
				tooltip = obj.tooltip_text
			if tooltip != null:
				tooltip_text = str(tooltip)
	else:
		unhovered.emit(meta)
		RTUtils.try_call(meta, FUNC_LINK_UNHOVERED, null, self)
		tooltip_text = ""

static func _get_tag_script(name: String) -> Script:
	return RTUtils.get_gd_script(name)

static func _align_from_style(style: RichParser.ParsedStyle) -> int:
	match style.align.to_lower():
		"center": return AlignMode.CENTER
		"right":  return AlignMode.RIGHT
		"fill":   return AlignMode.FILL
		_:        return AlignMode.LEFT

static func _is_punctuation(ch: String) -> bool:
	return ch.length() == 1 and _PUNCTUATION.contains(ch)

func _segments_to_items(segments: Array[RichParser.ParsedSegment]) -> void:
	_items.clear()
	var glyph_index := 0
	var shader_idx := 0
	var word_index := 0
	var prev_was_space := true
	var saw_word := false
	var max_lc := 1
	var seq_index := 0

	for segment in segments:
		var style := segment.style
		var align := _align_from_style(style)

		if segment.kind == &"asset":
			var asset := InlineItem.new()
			asset.kind = ItemKind.IMAGE if segment.asset_type == "image" else ItemKind.SCENE
			asset.align = align
			asset.sequence_index = seq_index
			asset.word_index = word_index
			asset.asset_id = segment.asset_id
			asset.attrs = segment.attrs
			asset.intro_t = 0.0
			asset.outro_t = 0.0
			# Build the same tag instances that surround this image position so
			# glyph_mask_arr[image_glyph_idx] is set correctly (e.g. fade applies).
			for td in style.tags:
				var tag_inst := _instantiate_tag(td, style)
				if tag_inst == null: continue
				asset.tags.append(tag_inst)
			asset.link_meta = style.link_meta

			var fh := _label_font_height()
			if asset.kind == ItemKind.IMAGE:
				asset.texture = RTUtils.get_texture(asset.asset_id)
				if asset.texture == null:
					continue
				asset.scene_node = _acquire_inline_node(asset)
				asset.size = _fit_inline_size(asset.texture.get_size(), asset.attrs, fh)
				asset.valign = String(asset.attrs.get("valign", "baseline"))
			else:
				asset.scene_node = _acquire_inline_node(asset)
				if asset.scene_node == null:
					push_warning("RichLabel: inline scene '%s' is not a CanvasItem; skipped." % asset.asset_id)
					continue
				if asset.scene_node is Control:
					# Controls only: their rectangle size is what we can lay out.
					var c := asset.scene_node as Control
					var natural := c.get_combined_minimum_size()
					if natural == Vector2.ZERO:
						natural = c.custom_minimum_size
					asset.size = _fit_inline_size(natural, asset.attrs, fh)
					asset.valign = String(asset.attrs.get("valign", "baseline"))
				else:
					push_warning("RichLabel: inline scene '%s' is not a Control; auto-fit disabled." % asset.asset_id)
					if "size" in asset.scene_node:
						asset.size = asset.scene_node.get("size")

			asset.index = glyph_index
			asset.shader_idx = shader_idx
			asset.advance = maxf(0.0, asset.size.x) + char_spacing
			shader_idx += 1
			glyph_index += 1
			_items.append(asset)
			seq_index += 1
			continue

		var text := segment.text
		if text == "":
			continue

		var base_font: Font = RTUtils.get_font(style.font_asset) if style.font_asset != "" \
			else (font if font else get_theme_default_font())
		var base_fs := style.font_size if style.font_size >= 0 else font_size
		var seg_adv := _shape_segment_advances(base_font, _resolved_font_size(base_fs), text) if shaping else PackedFloat32Array()

		for ci in text.length():
			var ch := text[ci]
			if ch == "\n":
				var br := LayoutItem.new()
				br.kind = ItemKind.LINE_BREAK
				br.align = align
				br.sequence_index = seq_index
				br.advance = 0.0
				_items.append(br)
				seq_index += 1
				continue

			var glyph := Glyph.new()
			glyph.kind = ItemKind.GLYPH
			glyph.character = ch
			glyph.align = align
			glyph.index = glyph_index
			if not (ch in ["", "\n", " ", "\t"]):
				glyph.shader_idx = shader_idx
				shader_idx += 1
			else:
				glyph.shader_idx = -1
			glyph.sequence_index = seq_index
			glyph.word_index = word_index
			glyph.seed = fposmod(sin(float(glyph_index) * 127.1 + glyph.character.unicode_at(0) * 311.7) * 43758.5453, 1.0)
			glyph.font = RTUtils.get_font(style.font_asset)
			glyph.font_size = style.font_size if style.font_size >= 0 else font_size
			var fill_col := style.color if style.color != RichParser.ParsedStyle.NO_COLOR else color
			glyph.fill_color = fill_col
			glyph.link_meta = style.link_meta
			glyph.tags = []

			if ch in [" ", "\t"]:
				if not prev_was_space:
					word_index += 1
				prev_was_space = true
			else:
				prev_was_space = false
				saw_word = true

			var layer_tags: Array[RichTag] = []
			for td in style.tags:
				var tag_inst := _instantiate_tag(td, style)
				if tag_inst == null: continue
				glyph.font = tag_inst.mutate_font(glyph.font)
				glyph.font_size = tag_inst.mutate_font_size(glyph.font_size)
				glyph.fill_color = tag_inst.mutate_color(glyph.fill_color)
				var fv := tag_inst.get("_tag_font_variation")
				if fv != null:
					glyph.font_variation_params.merge(fv, true)
				glyph.tags.append(tag_inst)
				if tag_inst.get_layer_count() > 0:
					var tid := tag_inst.get_tag_id()
					var replaced := false
					for li in layer_tags.size():
						if layer_tags[li].get_tag_id() == tid:
							layer_tags[li] = tag_inst
							replaced = true
							break
					if not replaced:
						layer_tags.append(tag_inst)

			# Glyph-wide default outline: injected after fill mutations so
			# SHIFTED mode derives from the glyph's final color. An explicit
			# [outline] in the span replaces it (same tag id wins). Behavior is
			# owned by the outline tag; this label only supplies the fill color.
			var def := _make_default_outline(glyph.fill_color)
			if def != null:
				glyph.tags.append(def)
				var def_tid := def.get_tag_id()
				var outline_replaced := false
				for li in layer_tags.size():
					if layer_tags[li].get_tag_id() == def_tid:
						layer_tags[li] = def
						outline_replaced = true
						break
				if not outline_replaced:
					layer_tags.append(def)

			# Glyph-wide default glow, same override rules as the outline.
			var dglow := _make_default_glow(glyph.fill_color)
			if dglow != null:
				glyph.tags.append(dglow)
				var gtid := dglow.get_tag_id()
				var greplaced := false
				for li in layer_tags.size():
					if layer_tags[li].get_tag_id() == gtid:
						layer_tags[li] = dglow
						greplaced = true
						break
				if not greplaced:
					layer_tags.append(dglow)

			var lc_count := 1
			for lt in layer_tags:
				lc_count += lt.get_layer_count()

			# Kerning-aware advance, valid only when tags didn't swap the
			# font/size away from what we shaped with.
			var eff_font := glyph.font if glyph.font else base_font
			if not seg_adv.is_empty() and ch != "\n" and ch != "\t" \
					and eff_font == base_font and glyph.font_size == base_fs \
					and ci < seg_adv.size() and seg_adv[ci] >= 0.0:
				glyph.advance_override = seg_adv[ci]
			
			glyph.layer_colors = PackedColorArray([glyph.fill_color])
			glyph.layer_sd_bias = PackedFloat32Array([0.0])
			glyph.layer_offsets = PackedVector2Array([Vector2.ZERO])
			glyph.layer_seeds = PackedFloat32Array([0.0])
			glyph.layer_feathers = PackedFloat32Array([0.0])
			glyph.layer_radius = PackedFloat32Array([0.0])
			for lt in layer_tags:
				for li in lt.get_layer_count():
					var cfg := lt.get_layer_config(li)
					glyph.layer_colors.append(cfg.get("color", Color.BLACK))
					glyph.layer_sd_bias.append(cfg.get("sd_bias", 0.0))
					glyph.layer_offsets.append(cfg.get("offset", Vector2.ZERO))
					glyph.layer_seeds.append(cfg.get("seed", 0.0))
					glyph.layer_feathers.append(cfg.get("feather", 0.0))
					glyph.layer_radius.append(float(cfg.get("radius_px", 0.0)))

			glyph.layer_count = lc_count

			max_lc = maxi(max_lc, lc_count)
			_items.append(glyph)
			glyph_index += 1
			seq_index += 1

	if saw_word and prev_was_space:
		word_index -= 1  # a trailing separator would count a phantom word
	_total_glyphs = shader_idx
	_total_words = word_index if saw_word else 0
	_total_layers = max_lc

func _instantiate_tag(td: RichParser.ParsedTag, style: RichParser.ParsedStyle) -> RichTag:
	var tag_name := String(td.name).strip_edges().to_lower()
	if tag_name == "": return null
	var tag_script := _get_tag_script(tag_name)
	if not tag_script is Script: return null
	var tag_inst: RichTag = tag_script.new()
	var props := style.to_props()
	for prop in props:
		if prop in tag_inst: tag_inst[prop] = props[prop]
	for kw in td.kwargs:
		if kw in tag_inst: tag_inst[kw] = td.kwargs[kw]
	tag_inst.init_from_args(td.args)
	return tag_inst

## Builds a glyph-wide default outline tag from the outline tag's configured
## `mode`/`value`/`hue_shift`/`size`/`color`. Returns null when the default
## mode is NONE. Color resolution lives on the tag; this only supplies the fill.
func _make_default_outline(fill: Color) -> RichTag:
	var tmpl := _default_outline
	if tmpl == null or not tmpl.call(&"default_is_active"):
		return null
	var t: RichTag = tmpl.get_script().new()
	t.set("outline_size", tmpl.get("outline_size"))
	t.set("outline_color", tmpl.call(&"resolve_color", fill))
	return t

## Builds a glyph-wide default glow tag from the glow tag's configured
## `mode`/`value`/`hue_shift`/etc. Returns null when the default mode is NONE.
func _make_default_glow(fill: Color) -> RichTag:
	var tmpl := _default_glow
	if tmpl == null or not tmpl.call(&"default_is_active"):
		return null
	var t: RichTag = tmpl.get_script().new()
	t.set("size_px", tmpl.get("size_px"))
	t.set("glow_color", tmpl.call(&"resolve_color", fill))
	return t

func _layout_items(items: Array[LayoutItem]) -> void:
	_items = items

	var lines: Array[LayoutLine] = []
	var wrap_w := size.x if autowrap and size.x > 0.0 else INF

	var cur := LayoutLine.new()
	var cursor_x := 0.0

	for item in items:
		if item.kind == ItemKind.LINE_BREAK:
			_push_line(lines, cur)
			cur = LayoutLine.new()
			cursor_x = 0.0
			continue

		var advance := _measure_item_advance(item)
		if autowrap and wrap_w != INF and cur.items.size() > 0 and cursor_x + advance > wrap_w:
			# Greedy word wrap: backtrack to the last breakable space so words
			# stay intact; hard-break only when a single item exceeds the width.
			var cut := -1
			for k in range(cur.items.size() - 1, -1, -1):
				var prev := cur.items[k]
				if prev is Glyph and (prev as Glyph).character in [" ", "\t"]:
					cut = k
					break
			var carry: Array[LayoutItem] = []
			if cut >= 0:
				for k in range(cut + 1, cur.items.size()):
					carry.append(cur.items[k])
				cur.items.resize(cut)  # drop the breaking space itself
			_push_line(lines, cur)
			cur = LayoutLine.new()
			cursor_x = 0.0
			for m in carry:
				if cur.items.is_empty() and m is Glyph and (m as Glyph).character in [" ", "\t"]:
					continue  # swallow spaces carried to the start of a line
				var madv := _measure_item_advance(m)
				m.line_index = lines.size()
				m.position = Vector2(cursor_x, 0.0)
				m.size = _measure_item_size(m)
				m.advance = madv
				cur.items.append(m)
				cursor_x += madv
				cur.width = cursor_x
				cur.ascent = maxf(cur.ascent, _item_ascent(m))
				cur.descent = maxf(cur.descent, _item_descent(m))

		item.line_index = lines.size()
		item.position = Vector2(cursor_x, 0.0)
		item.size = _measure_item_size(item)
		item.advance = advance
		cur.items.append(item)
		cursor_x += advance
		cur.width = cursor_x
		cur.ascent = maxf(cur.ascent, _item_ascent(item))
		cur.descent = maxf(cur.descent, _item_descent(item))

	_push_line(lines, cur)

	var total_h := 0.0
	var max_w := 0.0
	var populated := 0
	for i in lines.size():
		var line := lines[i]
		max_w = maxf(max_w, line.width)
		if line.items.is_empty():
			continue
		populated += 1
		total_h += line.ascent + line.descent
		if i < lines.size() - 1:
			total_h += line_spacing

	var content_w := max_w
	var container_w := content_w
	if size.x > 0.0:
		container_w = size.x if autowrap else maxf(size.x, content_w)

	var y := 0.0
	var extra_y := size.y - total_h
	if extra_y > 0.0:
		match vertical_alignment:
			VERTICAL_ALIGNMENT_CENTER:
				y = extra_y * 0.5
			VERTICAL_ALIGNMENT_BOTTOM:
				y = extra_y
			_:
				pass

	for line in lines:
		_place_line(line, container_w, y)
		y += line.ascent + line.descent + line_spacing

	# Populated-line count doubles as the LINE-stagger reveal denominator.
	_total_lines = maxi(1, populated)
	_content_width = content_w
	_content_height = total_h
	var min_size := Vector2(content_w, total_h)
	if _last_custom_minimum_size != min_size:
		_last_custom_minimum_size = min_size
		set_custom_minimum_size(min_size)

static func _push_line(lines: Array[LayoutLine], line: LayoutLine) -> void:
	line.index = lines.size()
	lines.append(line)

func _place_line(line: LayoutLine, container_w: float, y: float) -> void:
	var center_items: Array[LayoutItem]
	var left_items: Array[LayoutItem]
	var right_items: Array[LayoutItem]
	var fill_items: Array[LayoutItem]
	var groups := { AlignMode.CENTER: center_items, AlignMode.RIGHT: right_items, AlignMode.FILL: fill_items, AlignMode.LEFT: left_items }
	for item in line.items:
		groups[item.align].append(item)
	
	var left_w := _group_width(left_items)
	var center_w := _group_width(center_items)
	var right_w := _group_width(right_items)
	var fill_extra := maxf(0.0, container_w - (left_w + center_w + right_w + _group_width(fill_items)))
	var fill_spaces := _count_spaces(fill_items)
	var fill_step := fill_extra / float(fill_spaces) if fill_spaces > 0 else 0.0

	var has_explicit_alignment := center_items.size() > 0 or right_items.size() > 0 or fill_items.size() > 0
	var x := 0.0
	if not has_explicit_alignment:
		match horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER:
				x = maxf(0.0, (container_w - left_w) * 0.5)
			HORIZONTAL_ALIGNMENT_RIGHT:
				x = maxf(0.0, container_w - left_w)
	for item in left_items:
		_apply_item_position(item, x, y, line)
		x += _item_draw_advance(item, fill_step)

	if center_items.size() > 0:
		var remaining_left := left_w
		var remaining_right := right_w
		var center_x := maxf(remaining_left, (container_w - center_w) * 0.5)
		center_x = minf(center_x, maxf(remaining_left, container_w - remaining_right - center_w))
		var cx := center_x
		for item in center_items:
			_apply_item_position(item, cx, y, line)
			cx += _item_draw_advance(item, fill_step)

	if right_items.size() > 0:
		var rx := maxf(0.0, container_w - right_w)
		for item in right_items:
			_apply_item_position(item, rx, y, line)
			rx += _item_draw_advance(item, fill_step)

	for item in fill_items:
		_apply_item_position(item, x, y, line)
		x += _item_draw_advance(item, fill_step)

func _apply_item_position(item: LayoutItem, x: float, y: float, line: LayoutLine) -> void:
	item.position = Vector2(x, y)
	item.line_index = line.index
	item.baseline = Vector2(0.0, line.ascent)
	if item is InlineItem and item.scene_node is Control:
		var ii := item as InlineItem
		var c := item.scene_node as Control
		# Default: bottom edge sits on the baseline.
		var yy := y + line.ascent - ii.size.y
		match ii.valign:
			"top":
				yy = y
			"center":
				yy = y + (line.ascent - ii.size.y) * 0.5
			_:
				pass
		c.position = Vector2(x, yy)
		if ii.size != Vector2.ZERO:
			c.size = ii.size

func _item_draw_advance(item: LayoutItem, fill_step: float) -> float:
	if item is Glyph:
		var g := item as Glyph
		return g.advance + fill_step if g.character == " " and fill_step > 0.0 else g.advance
	return item.advance

func _count_spaces(items: Array[LayoutItem]) -> int:
	var total := 0
	for item in items:
		if item is Glyph and (item as Glyph).character == " ":
			total += 1
	return total

func _group_width(items: Array[LayoutItem]) -> float:
	var w := 0.0
	for item in items:
		w += item.advance
	return w

func _item_ascent(item: LayoutItem) -> float:
	if item is Glyph:
		var g := item as Glyph
		var fs := _resolved_font_size(g.font_size)
		var f := _get_font_for_glyph(g)
		return f.get_ascent(fs) if f else 0.0
	if item is InlineItem:
		return item.size.y
	return 0.0

func _item_descent(item: LayoutItem) -> float:
	if item is Glyph:
		var g := item as Glyph
		var fs := _resolved_font_size(g.font_size)
		var f := _get_font_for_glyph(g)
		return f.get_descent(fs) if f else 0.0
	return 0.0

func _measure_item_size(item: LayoutItem) -> Vector2:
	if item is Glyph:
		var g := item as Glyph
		var fs := _resolved_font_size(g.font_size)
		var f := _get_font_for_glyph(g)
		if f == null:
			return Vector2.ZERO
		var ch := "    " if g.character == "\t" else g.character
		var w := g.advance_override if g.advance_override >= 0.0 else f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var h := f.get_ascent(fs) + f.get_descent(fs)
		return Vector2(w, h)
	if item is InlineItem:
		return (item as InlineItem).size
	return Vector2.ZERO

func _measure_item_advance(item: LayoutItem) -> float:
	if item is Glyph:
		return _measure_item_size(item).x + char_spacing
	if item is InlineItem:
		return (item as InlineItem).advance
	return 0.0

func _get_font_for_glyph(g: Glyph) -> Font:
	var base := g.font if g.font != null else font
	if base == null:
		base = get_theme_default_font()
	if g.font_variation_params == null or g.font_variation_params.is_empty() or base == null:
		return base
	if g._font_variation_cache != null:
		return g._font_variation_cache
	var fv := FontVariation.new()
	fv.base_font = base
	for k in _FONT_VARIATION_MAP:
		if g.font_variation_params.has(k):
			fv.set(_FONT_VARIATION_MAP[k], float(g.font_variation_params[k]))
	if g.font_variation_params.has("italic"):
		fv.variation_slant = ITALIC_SLANT if bool(g.font_variation_params["italic"]) else 0.0
	g._font_variation_cache = fv
	return fv

func _get_configuration_warnings() -> PackedStringArray:
	if progress != 0.0:
		return ["Characters may be hidden if progress != 0.0."]
	return []

func _draw() -> void:
	if material == null:
		_ensure_shader_material()

	if use_batched_mesh and not _batch_surfaces.is_empty():
		var ci := get_canvas_item()
		for s in _batch_surfaces:
			RenderingServer.canvas_item_add_mesh(ci, (s.mesh as ArrayMesh).get_rid(), Transform2D(), Color(1, 1, 1, 1), s.tex)
		return

	for layer_i in range(_total_layers - 1, 0, -1):
		for item in _items:
			if item.kind == ItemKind.GLYPH:
				_draw_glyph_layer(item as Glyph, layer_i)

	for item in _items:
		if item.kind == ItemKind.GLYPH:
			_draw_glyph_layer(item as Glyph, 0)

## Bakes every visible glyph layer into one triangle mesh per font atlas,
## replacing hundreds/thousands of draw_char commands with a single
## canvas_item_add_mesh per texture. Identity encoding (COLOR.r/g) is
## identical to the draw_char path, so the generated shader is unchanged.
func _build_batch_meshes() -> void:
	_batch_surfaces.clear()
	if not use_batched_mesh or _items.is_empty():
		return

	var ts := TextServerManager.get_primary_interface()
	var order: Array[RID] = []
	var builders := {}  # tex RID -> { v, u, c, i, n }

	for layer_i in range(_total_layers - 1, -1, -1):
		for item in _items:
			if item.kind != ItemKind.GLYPH:
				continue
			var g := item as Glyph
			if g.character in ["", "\n", " ", "\t"] or layer_i >= g.layer_count:
				continue
			var font_used := _get_font_for_glyph(g)
			if font_used == null:
				continue
			var rids := font_used.get_rids()
			if rids.is_empty():
				continue
			var fr: RID = rids[0]
			var fs_int := _resolved_font_size(g.font_size)
			var gid := ts.font_get_glyph_index(fr, fs_int, g.character.unicode_at(0), 0)
			if gid <= 0:
				continue
			var fsz := Vector2i(fs_int, 0)
			var gsz := ts.font_get_glyph_size(fr, fsz, gid)
			if gsz.x <= 0.0 or gsz.y <= 0.0:
				continue
			var tex_rid := ts.font_get_glyph_texture_rid(fr, fsz, gid)
			if not tex_rid.is_valid():
				continue
			# uv rect arrives in atlas PIXELS — normalize into 0..1 sampler space
			# using the real texture dimensions.
			var tex_obj := RenderingServer.texture_2d_get(tex_rid)
			if tex_obj == null:
				continue
			var tex_size: Vector2 = tex_obj.get_size()
			if tex_size.x <= 0.0 or tex_size.y <= 0.0:
				continue
			var uvr := ts.font_get_glyph_uv_rect(fr, fsz, gid)
			if uvr.size.x <= 0.0 or uvr.size.y <= 0.0:
				continue
			var uv_tl := uvr.position / tex_size
			var uv_br := uvr.end / tex_size

			if not builders.has(tex_rid):
				order.append(tex_rid)
				builders[tex_rid] = {
					v = PackedVector2Array(),
					u = PackedVector2Array(),
					c = PackedColorArray(),
					i = PackedInt32Array(),
					n = 0,
				}
			var b: Dictionary = builders[tex_rid]

			var base := g.position + g.baseline
			if layer_i > 0 and layer_i < g.layer_offsets.size():
				base += g.layer_offsets[layer_i]
			var tl: Vector2 = base + ts.font_get_glyph_offset(fr, fsz, gid)
			var br := tl + gsz
			var col := Color(
				float(g.shader_idx) / float(max(1, _total_glyphs - 1)),
				float(layer_i) / float(max(1, _total_layers - 1)),
				0.0, 1.0)

			var n := int(b.n)
			b.v.append_array(PackedVector2Array([tl, Vector2(br.x, tl.y), br, Vector2(tl.x, br.y)]))
			b.u.append_array(PackedVector2Array([uv_tl, Vector2(uv_br.x, uv_tl.y), uv_br, Vector2(uv_tl.x, uv_br.y)]))
			b.c.append(col); b.c.append(col); b.c.append(col); b.c.append(col)
			b.i.append_array(PackedInt32Array([n, n + 1, n + 2, n, n + 2, n + 3]))
			b.n = n + 4

	for tex_rid in order:
		var b: Dictionary = builders[tex_rid]
		var arrs := []
		arrs.resize(Mesh.ARRAY_MAX)
		arrs[Mesh.ARRAY_VERTEX] = b.v
		arrs[Mesh.ARRAY_TEX_UV] = b.u
		arrs[Mesh.ARRAY_COLOR] = b.c
		arrs[Mesh.ARRAY_INDEX] = b.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
		_batch_surfaces.append({ mesh = mesh, tex = tex_rid })

## Draws a specific layer of a glyph with its index encoded in COLOR.r and layer in COLOR.g.
func _draw_glyph_layer(glyph: Glyph, layer_i: int) -> void:
	if layer_i >= glyph.layer_count:
		return
	if glyph.character in ["", "\n", " ", "\t"]:
		return
	var font_used := _get_font_for_glyph(glyph)
	if font_used == null:
		return
	var r := float(glyph.shader_idx) / float(max(1, _total_glyphs - 1)) if _total_glyphs > 1 else 0.0
	var draw_pos := glyph.position + glyph.baseline
	
	if layer_i > 0:
		draw_char(font_used, draw_pos + glyph.layer_offsets[layer_i], glyph.character, _resolved_font_size(glyph.font_size), Color(r, float(layer_i) / float(max(1, _total_layers - 1)), 0.0, 1.0))
	else:
		draw_char(font_used, draw_pos, glyph.character, _resolved_font_size(glyph.font_size), Color(r, 0.0, 0.0, 1.0))

func _label_font_height() -> float:
	var f := font if font else get_theme_default_font()
	var fs := maxi(1, _resolved_font_size(font_size))
	return f.get_height(fs) if f else float(fs)

## Computes the laid-out size of an inline image/scene from its natural size,
## the markup attributes and the surrounding line height.
##
## Supported attributes:
##   width/w, height/h  — explicit size (single one keeps aspect ratio)
##   fit=line (default) — shrink to the line height when taller
##   fit=none           — never rescale
##   fit=contain|cover  — scale to fill an explicit w*h box
##   valign             — baseline (default) | top | center | bottom
func _fit_inline_size(natural: Vector2, attrs: Dictionary, font_height: float) -> Vector2:
	var sz := natural
	if sz.x <= 0.0 or sz.y <= 0.0:
		return sz
	var wa := _num_attr(attrs, ["width", "w"])
	var ha := _num_attr(attrs, ["height", "h"])
	if ha > 0.0:
		sz.y = ha
		if wa <= 0.0:
			sz.x = natural.x * (ha / natural.y)
	if wa > 0.0:
		sz.x = wa
		if ha <= 0.0:
			sz.y = natural.y * (wa / natural.x)
	var mode := String(attrs.get("fit", ""))
	if mode == "":
		# Explicit sizes are respected as-is; otherwise shrink to the text line.
		mode = "none" if (wa > 0.0 or ha > 0.0) else "line"
	match mode:
		"contain":
			if wa > 0.0 and ha > 0.0:
				sz = natural * minf(wa / natural.x, ha / natural.y)
		"cover":
			if wa > 0.0 and ha > 0.0:
				sz = natural * maxf(wa / natural.x, ha / natural.y)
		"line":
			if sz.y > font_height and font_height > 0.0:
				sz *= font_height / sz.y
		"none", _:
			pass
	return sz

static func _num_attr(attrs: Dictionary, keys: Array) -> float:
	for k in keys:
		var v: Variant = attrs.get(k)
		if v == null:
			continue
		if v is float or v is int:
			return float(v)
		if v is String and (v as String).is_valid_float():
			return (v as String).to_float()
	return -1.0

## Returns a reusable node for an inline item — pooled between rebuilds to
## avoid free/instantiate churn (and the flicker that comes with it).
func _acquire_inline_node(asset: InlineItem) -> CanvasItem:
	var bucket: Array = _inline_pool.get_or_add(asset.asset_id, [])
	while not bucket.is_empty():
		var n: CanvasItem = bucket.pop_back()
		if is_instance_valid(n):
			if asset.kind == ItemKind.IMAGE and n is TextureRect:
				(n as TextureRect).texture = asset.texture
			return n
	if asset.kind == ItemKind.IMAGE:
		var tr := TextureRect.new()
		tr.texture = asset.texture
		tr.ignore_texture_size = true
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tr
	return RTUtils.get_scene(asset.asset_id) as CanvasItem

func _sync_inline_nodes() -> void:
	for item in _items:
		if not item is InlineItem or item.scene_node == null:
			continue
		var ii := item as InlineItem
		if ii.scene_node.get_parent() != self:
			add_child(ii.scene_node)
		if ii.scene_node is Control:
			var c := ii.scene_node as Control
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if not c.resized.is_connected(_on_inline_geometry_changed):
				c.resized.connect(_on_inline_geometry_changed)
			if not c.minimum_size_changed.is_connected(_on_inline_geometry_changed):
				c.minimum_size_changed.connect(_on_inline_geometry_changed)
	_request_inline_relayout()

func _release_inline_nodes() -> void:
	for item in _items:
		if item is InlineItem and item.scene_node != null:
			var ii := item as InlineItem
			var n := ii.scene_node
			if n.get_parent() == self:
				remove_child(n)
			var bucket: Array = _inline_pool.get_or_add(ii.asset_id, [])
			bucket.append(n)
			while bucket.size() > INLINE_POOL_LIMIT:
				var old: Node = bucket.pop_front()
				if is_instance_valid(old):
					old.free()

## Scenes may only know their real (theme-dependent) minimum size after
## entering the tree; re-measure on the next frame and relayout if changed.
func _on_inline_geometry_changed() -> void:
	_request_inline_relayout()

func _request_inline_relayout() -> void:
	if _inline_relayout_pending:
		return
	_inline_relayout_pending = true
	_do_inline_relayout.call_deferred()

func _do_inline_relayout() -> void:
	_inline_relayout_pending = false
	if not is_inside_tree() or _items.is_empty():
		return
	var changed := false
	for item in _items:
		if not item is InlineItem:
			continue
		var ii := item as InlineItem
		if ii.scene_node == null or not (ii.scene_node is Control):
			continue
		var c := ii.scene_node as Control
		var natural := c.get_combined_minimum_size()
		if natural == Vector2.ZERO:
			natural = c.custom_minimum_size
		var fitted := _fit_inline_size(natural, ii.attrs, _label_font_height())
		if not fitted.is_equal_approx(ii.size):
			ii.size = fitted
			ii.advance = maxf(0.0, fitted.x) + char_spacing
			changed = true
	if changed:
		_layout_items(_items)
		_apply_reveal_positions(_items)
		_build_link_data(_items)
		_update_shader()
		_build_batch_meshes()
		queue_redraw()

func _ensure_shader_material() -> void:
	if not material:
		material = ShaderMaterial.new()
		material.resource_local_to_scene = true
	var sm: ShaderMaterial = material
	if not sm.shader:
		sm.shader = Shader.new()
		sm.shader.resource_local_to_scene = true
		sm.shader.code = "shader_type canvas_item; render_mode unshaded; void fragment(){ COLOR = texture(TEXTURE, UV) * COLOR; }"

func _update_shader() -> void:
	var seen := {}
	var unique_tags: Array[RichTag] = []
	# Collect unique tags from both glyphs AND images so effect bits are assigned.
	for item in _items:
		for t in item.tags:
				var id := t.get_tag_id()
				if not seen.has(id):
					seen[id] = true
					unique_tags.append(t)
	var bits := {}
	for i in unique_tags.size():
		bits[unique_tags[i].get_tag_id()] = 1 << i

	# Geometry arrays (origin/size/font_size) are only needed when some tag
	# contributes vertex code that reads them.
	var need_geom := false
	for t in unique_tags:
		if t.get_vertex().strip_edges() != "":
			need_geom = true
			break
	var has_imgs := false
	for item in _items:
		if item is InlineItem:
			has_imgs = true
			break
	# Bitmap-font outline/glow dilation is only emitted when some layer wants it.
	var need_dilation := false
	for item in _items:
		if item is Glyph:
			for r in (item as Glyph).layer_radius:
				if r > 0.0:
					need_dilation = true
					break
		if need_dilation:
			break
	# Glow-style layers (feather > 0 with a reach): enable the MSDF distance-
	# field dilation kernel.
	var need_glow := false
	for item in _items:
		if item is Glyph:
			var gg := item as Glyph
			var n := mini(gg.layer_count, gg.layer_feathers.size())
			for li in n:
				if gg.layer_feathers[li] > 0.0 \
						and li < gg.layer_radius.size() and gg.layer_radius[li] > 0.0:
					need_glow = true
					break
		if need_glow:
			break

	# Reuse compiled shaders across rebuilds — regenerating identical code
	# would otherwise trigger a GPU pipeline rebuild on every edit.
	var shader_code := _build_shader_code(unique_tags, bits, has_imgs, need_dilation, need_glow)
	var code_hash := shader_code.hash()
	var shader: Shader = _shader_cache.get(code_hash)
	if shader == null:
		shader = Shader.new()
		shader.code = shader_code
		if _shader_cache.size() >= SHADER_CACHE_MAX:
			_shader_cache.clear()
		_shader_cache[code_hash] = shader
	if material.shader != shader:
		material.shader = shader

	set_instance_shader_parameter(&"is_text", true)
	set_instance_shader_parameter(&"inst_index", 0)

	var f := font if font else get_theme_default_font()
	var font_file: FontFile = f if f is FontFile\
		else (f.base_font if f is FontVariation and f.base_font is FontFile else null)
	var is_msdf := font_file != null and font_file.multichannel_signed_distance_field
	var px_range := font_file.msdf_pixel_range if is_msdf else 8.0
	_set_shader_param(&"msdf_enabled", is_msdf)
	_set_shader_param(&"msdf_pixel_range", px_range)

	_set_shader_param(&"progress", progress)
	_set_shader_param(&"intro_stagger", anim_intro_stagger)
	_set_shader_param(&"outro_stagger", anim_outro_stagger)

	_update_link_shader_state()

	var glyph_array_size := maxi(1, _total_glyphs)
	var glyph_mask_arr := RTUtils.packedInt32(glyph_array_size)
	var font_sizes := RTUtils.packedFloat32(glyph_array_size)
	var intro_t := RTUtils.packedFloat32(glyph_array_size)
	var seeds := RTUtils.packedFloat32(glyph_array_size)
	var outro_t := RTUtils.packedFloat32(glyph_array_size)
	var origins := RTUtils.packedVec2(glyph_array_size) if need_geom else PackedVector2Array()
	var sizes := RTUtils.packedVec2(glyph_array_size) if need_geom else PackedVector2Array()
	var link_indices := RTUtils.packedInt32(glyph_array_size, -1)

	var layer_array_size := maxi(1, glyph_array_size * _total_layers)
	var layer_color_arr := RTUtils.packedColor(layer_array_size)
	var layer_sd_bias_arr := RTUtils.packedFloat32(layer_array_size)
	var layer_feather_arr := RTUtils.packedFloat32(layer_array_size)
	var layer_radius_arr := RTUtils.packedFloat32(layer_array_size) if need_dilation else PackedFloat32Array()

	for item in _items:
		var idx := item.shader_idx
		if idx >= 0 and idx < glyph_array_size:
			var m := 0
			for t in item.tags:
				m |= int(bits.get(t.get_tag_id(), 0))
			glyph_mask_arr[idx] = m

		if item is InlineItem:
			_sync_inline_shader_params(item, glyph_mask_arr, need_geom)
		elif item is Glyph:
			var g := item as Glyph
			if idx >= 0 and idx < glyph_array_size:
				seeds[idx] = g.seed
				intro_t[idx] = g.intro_t
				outro_t[idx] = g.outro_t
				if g.link_index >= 0:
					link_indices[idx] = mini(g.link_index, MAX_LINKS - 1)
				if need_geom:
					origins[idx] = g.position + g.baseline
					sizes[idx] = g.size
					font_sizes[idx] = _resolved_font_size(g.font_size)
			if idx < 0:
				continue
			for layer_i in g.layer_count:
				if layer_i < _total_layers:
					var lidx = layer_i * glyph_array_size + idx
					if lidx < layer_array_size:
						layer_color_arr[lidx] = g.layer_colors[layer_i]
						layer_sd_bias_arr[lidx] = g.layer_sd_bias[layer_i]
						layer_feather_arr[lidx] = g.layer_feathers[layer_i]
						if need_dilation and layer_i < g.layer_radius.size():
							layer_radius_arr[lidx] = g.layer_radius[layer_i]

	_set_shader_param(&"glyph_mask_arr", glyph_mask_arr)

	_set_shader_param(&"layer_color_arr", layer_color_arr)
	_set_shader_param(&"layer_sd_bias_arr", layer_sd_bias_arr)
	_set_shader_param(&"layer_feather_arr", layer_feather_arr)
	if need_dilation:
		_set_shader_param(&"layer_radius_arr", layer_radius_arr)

	_set_shader_param(&"glyph_seed_arr", seeds)
	if not _link_data.is_empty():
		_set_shader_param(&"glyph_link_idx", link_indices)
	if need_geom:
		_set_shader_param(&"glyph_origin_arr", origins)
		_set_shader_param(&"glyph_size_arr", sizes)
		_set_shader_param(&"glyph_font_size_arr", font_sizes)
	_set_shader_param(&"glyph_intro_t", intro_t)
	_set_shader_param(&"glyph_outro_t", outro_t)

func _resolved_font_size(value: int) -> int:
	return value if value > 0 else get_theme_default_font_size()

## Kerning-aware per-character advances for a segment. Newline positions map
## to -1. Uses shaped bigram measurement so pairwise kerning is captured;
## ligatures/contextual forms fall back to naive sizing naturally.
static func _shape_segment_advances(f: Font, fs: int, text: String) -> PackedFloat32Array:
	var n := text.length()
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(-1.0)
	if f == null or n == 0:
		return out
	for i in n:
		var ch := text[i]
		if ch == "\n":
			continue
		out[i] = _shaped_advance(f, fs, text[i - 1] if i > 0 else "", ch)
	return out

static func _shaped_advance(f: Font, fs: int, prev: String, ch: String) -> float:
	var sw := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if prev != "":
		var naive2 := f.get_string_size(prev, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sw
		var pair := f.get_string_size(prev + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		sw += pair - naive2
	return maxf(0.0, sw)

func _apply_reveal_positions(items: Array[LayoutItem]) -> void:
	# Denominators use counts (not max indices) so the last item's t stays
	# below 1.0 and every cascade actually finishes with the final element.
	var ms := maxf(1.0, float(items.size()))
	var mw := maxf(1.0, float(_total_words + 1))
	var ml := maxf(1.0, float(_total_lines))
	for item in items:
		item.intro_t = _reveal_t(item, anim_intro_mode, ms, mw, ml)
		item.outro_t = _reveal_t(item, anim_outro_mode, ms, mw, ml)

func _reveal_t(item: LayoutItem, mode: StaggerMode, ms: float, mw: float, ml: float) -> float:
	match mode:
		StaggerMode.CHARACTER: return float(item.sequence_index) / ms
		StaggerMode.WORD:      return float(item.word_index)     / mw
		StaggerMode.LINE:      return float(item.line_index)     / ml
		_: return 0.0

## Returns tween breakpoints (progress value + pause duration) for items that
## should trigger a real pause during playback. Only applies in CHARACTER mode
## since that is the only mode with a meaningful per-item cascade order.
## intro=true builds breakpoints for the intro pass, false for the outro pass.
func _build_pause_breakpoints(mode: StaggerMode, stagger: float, intro: bool) -> Array[Dictionary]:
	if mode != StaggerMode.CHARACTER:
		return []
	if not pause_on_punctuation and not pause_on_newline:
		return []
	var bps: Array[Dictionary] = []
	for item in _items:
		var pause_dur := 0.0
		if pause_on_punctuation and item is Glyph and _is_punctuation((item as Glyph).character):
			pause_dur = punctuation_pause
		elif pause_on_newline and item.kind == ItemKind.LINE_BREAK:
			pause_dur = newline_pause
		if pause_dur <= 0.0:
			continue
		var t := item.intro_t if intro else item.outro_t
		# Compute the progress value at which this item is fully revealed/hidden.
		# Derived from the shader formula: item is complete when its local anim=1.
		var p_full: float
		if intro:
			# p_intro = t * stagger + w_intro  =>  progress = stagger * (t - 1)
			p_full = stagger * (t - 1.0)
		else:
			# p_outro = t * stagger + w_outro  =>  progress = 1 - stagger * (1 - t)
			p_full = 1.0 - stagger * (1.0 - t)
		bps.append({p = p_full, dur = pause_dur})
	bps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.p < b.p)
	return bps

func _sync_inline_shader_params(inline: InlineItem, masks: PackedInt32Array, need_geom: bool) -> void:
	var node: CanvasItem = inline.scene_node
	if not node: return
	node.material = material
	node.use_parent_material = false
	node.set_instance_shader_parameter(&"is_text", false)
	node.set_instance_shader_parameter(&"inst_index", inline.shader_idx)
	node.set_instance_shader_parameter(&"inst_seed", 0.0)
	node.set_instance_shader_parameter(&"inst_intro_t", inline.intro_t)
	node.set_instance_shader_parameter(&"inst_outro_t", inline.outro_t)
	if inline.shader_idx >= 0 and masks.size() > inline.shader_idx:
		node.set_instance_shader_parameter(&"inst_effects_mask", masks[inline.shader_idx])
	if need_geom:
		var sz := inline.size if inline.size != Vector2.ZERO else (node.size as Vector2 if "size" in node else Vector2.ZERO)
		node.set_instance_shader_parameter(&"inst_origin", inline.position + inline.baseline)
		node.set_instance_shader_parameter(&"inst_size", sz)
		node.set_instance_shader_parameter(&"inst_font_size", sz.y)
	if inline.link_index >= 0:
		node.set_instance_shader_parameter(&"inst_link_idx", mini(inline.link_index, MAX_LINKS - 1))
	else:
		node.set_instance_shader_parameter(&"inst_link_idx", -1)

static func _strip_comments(s: String) -> String:
	var out := ""
	for line in s.split("\n"):
		out += (line.split("//", true, 1)[0].strip_edges() if "//" in line else line.strip_edges())
	return out

## Rewrites the engine TIME token to the label's own fx_time uniform so
## effects respect time_scale and pause state.
static func _rewrite_fx_time(snippet: String) -> String:
	if _time_token_re == null:
		_time_token_re = RegEx.create_from_string("\\bTIME\\b")
	return _time_token_re.sub(snippet, "fx_time", true)

func _build_shader_code(tags: Array[RichTag], bits: Dictionary, has_imgs: bool, need_dilation: bool, need_glow: bool) -> String:
	var max_arr  := _get_max_array_size()
	var has_lnks := not _link_data.is_empty()
	var link_cap := maxi(1, mini(_link_data.size(), MAX_LINKS))
	var arr_sz   := clampi(_total_glyphs, 1, max_arr)
	var layer_sz := clampi(_total_glyphs * _total_layers, 1, max_arr)
	var gcf      := "%.1f" % maxf(1.0, _total_glyphs - 1.0)
	var lcf      := "%.1f" % maxf(1.0, _total_layers - 1.0)

	# -- Collect tag contributions ----------------------------------------
	var helpers:    Array[String] = []
	var vert_calls: Array[String] = []
	var frag_calls: Array[String] = []
	for t in tags:
		var uid := t.get_tag_id()
		var bit := int(bits.get(uid, 0))
		var h   := _rewrite_fx_time(t.get_helper_funcs().strip_edges())
		var vf  := _rewrite_fx_time(t.get_vertex().strip_edges())
		var ff  := _rewrite_fx_time(t.get_fragment().strip_edges())
		if h:  helpers.append(_strip_comments(h))
		if vf: vert_calls.append("/* [%s] */ if ((mask & %d) != 0) { %s }" % [uid, bit, _strip_comments(vf)])
		if ff: frag_calls.append("/* [%s] */ if ((mask & %d) != 0) { %s }" % [uid, bit, _strip_comments(ff)])
	# Effects may reference the label clock either via engine TIME (rewritten
	# above) or by naming fx_time directly — both need the uniform.
	for s in helpers + vert_calls + frag_calls:
		if "fx_time" in s:
			_uses_fx_clock = true
			break

	# Geometry arrays (origin/gsz/font_size) are only needed when some tag's
	# vertex code actually reads them.
	var need_geom := not vert_calls.is_empty()

	# Auto-include utility helpers if referenced anywhere in tag code.
	const UTIL_HELPERS := {
		"linear(":          "float linear(float t) { return clamp(t, 0.0, 1.0); }",
		"easeout_cubic(":   "float easeout_cubic(float t) { t = clamp(t, 0.0, 1.0); float i = 1.0 - t; return 1.0 - i*i*i; }",
		"easein_cubic(":    "float easein_cubic(float t) { t = clamp(t, 0.0, 1.0); return t*t*t; }",
		"easeout_back(":    "float easeout_back(float t) { t = clamp(t, 0.0, 1.0); const float c1 = 1.70158; const float c3 = 2.70158; return 1.0 + c3*pow(t-1.0,3.0) + c1*pow(t-1.0,2.0); }",
		"easeout_elastic(": "float easeout_elastic(float t) { t = clamp(t, 0.0, 1.0); if (t <= 0.0 || t >= 1.0) return t; return pow(2.0,-10.0*t)*sin((t*10.0-0.75)*2.09439510239)+1.0; }",
		"easeinout_cubic(": "float easeinout_cubic(float t) { t = clamp(t, 0.0, 1.0); return t < 0.5 ? 4.0*t*t*t : 1.0-pow(-2.0*t+2.0,3.0)/2.0; }",
		"hash(":            "float hash(float x) { return fract(sin(x*12.9898)*43758.5453); }",
		"hash2(":           "float hash2(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }",
	}
	var tag_code := " ".join(PackedStringArray(helpers + vert_calls + frag_calls))
	for sig in UTIL_HELPERS:
		if sig in tag_code:
			helpers.append(UTIL_HELPERS[sig])

	# -- Common vars: decoded per-glyph state, shared by vert + frag -------
	var cv: Array[String] = [
		"float w_intro = max(0.001, 1.0 - intro_stagger);",
		"float w_outro = max(0.001, 1.0 - outro_stagger);",
		"float p_intro = clamp(progress + 1.0, 0.0, 1.0);",
		"float p_outro = clamp(progress,       0.0, 1.0);",
	]
	if has_imgs:
		cv.append_array([
			"int layer; int glyph; int mask; float base_intro_t; float base_outro_t; float seed;",
			"if (is_text) {",
			"\tlayer        = int(clamp(rl_xfer.y * %s + 0.5, 0.0, %s));" % [lcf, lcf],
			"\tglyph        = int(clamp(rl_xfer.x * %s + 0.5, 0.0, %s));" % [gcf, gcf],
			"\tmask         = glyph_mask_arr[glyph];",
			"\tbase_intro_t = glyph_intro_t[glyph];",
			"\tbase_outro_t = glyph_outro_t[glyph];",
			"\tseed         = glyph_seed_arr[glyph];",
		])
		if has_lnks: cv.append("\tfloat link_state = link_states_arr[min(int(glyph_link_idx[glyph]), %d)];" % (link_cap - 1))
		cv.append_array([
			"} else {",
			"\tlayer        = 0;",
			"\tglyph        = inst_index;",
			"\tmask         = inst_effects_mask;",
			"\tbase_intro_t = inst_intro_t;",
			"\tbase_outro_t = inst_outro_t;",
			"\tseed         = inst_seed;",
		])
		if has_lnks: cv.append("\tfloat link_state = link_states_arr[int(clamp(inst_link_idx, 0.0, %.1f))];" % float(link_cap - 1))
		cv.append("}")
	else:
		cv.append_array([
			"int   layer        = int(clamp(rl_xfer.y * %s + 0.5, 0.0, %s));" % [lcf, lcf],
			"int   glyph        = int(clamp(rl_xfer.x * %s + 0.5, 0.0, %s));" % [gcf, gcf],
			"int   mask         = glyph_mask_arr[glyph];",
			"float base_intro_t = glyph_intro_t[glyph];",
			"float base_outro_t = glyph_outro_t[glyph];",
			"float seed         = glyph_seed_arr[glyph];",
		])
		if has_lnks: cv.append("float link_state = link_states_arr[min(int(glyph_link_idx[glyph]), %d)];" % (link_cap - 1))
	cv.append_array([
		"float intro_t = clamp((p_intro - base_intro_t * intro_stagger) / w_intro, 0.0, 1.0);",
		"float outro_t = clamp((p_outro - base_outro_t * outro_stagger) / w_outro, 0.0, 1.0);",
		"float anim    = intro_t * (1.0 - outro_t);",
	])
	var common_vars := "\n\t".join(PackedStringArray(cv))

	# -- Vertex-only geometry locals ---------------------------------------
	var geom_vars := ""
	if need_geom:
		if has_imgs:
			geom_vars = "\n\t".join(PackedStringArray([
				"vec2  origin    = is_text ? glyph_origin_arr[glyph] : inst_origin;",
				"vec2  gsz       = is_text ? glyph_size_arr[glyph] : inst_size;",
				"float font_size = is_text ? glyph_font_size_arr[glyph] : inst_font_size;",
			]))
		else:
			geom_vars = "\n\t".join(PackedStringArray([
				"vec2  origin    = glyph_origin_arr[glyph];",
				"vec2  gsz       = glyph_size_arr[glyph];",
				"float font_size = glyph_font_size_arr[glyph];",
			]))

	# -- Build output sections, then join ---------------------------------
	var out: PackedStringArray = [
		"// WARNING: Generated by rich_label.gd. Your changes will be overwritten.",
		"shader_type canvas_item;",
		# Glyph/layer identity rides this varying from the vertex stage.
		# Fragment COLOR arrives pre-multiplied by the texture sample, which
		# corrupts the encoding for MSDF fonts (RGB holds distance data);
		# vertex COLOR is still raw.
		"varying vec2 rl_xfer;",
	]

	# Instance uniforms — only present when inline images exist.
	if has_imgs:
		var iu: PackedStringArray = [
			"instance uniform bool  is_text          = true;",
			"instance uniform int   inst_index       = 0;",
			"instance uniform float inst_seed        = 0.0;",
			"instance uniform float inst_intro_t     = 0.0;",
			"instance uniform float inst_outro_t     = 0.0;",
			"instance uniform int   inst_effects_mask = 0;",
		]
		if need_geom:
			iu.append_array([
				"instance uniform vec2  inst_origin      = vec2(0.0);",
				"instance uniform vec2  inst_size        = vec2(0.0);",
				"instance uniform float inst_font_size   = 0.0;",
			])
		if has_lnks: iu.append("instance uniform float inst_link_idx = -1.0;")
		out.append("\n".join(iu))

	# Shared uniforms.
	var su: PackedStringArray = [
		"group_uniforms MSDF;",
		"uniform bool  msdf_enabled     = false;",
		"uniform float msdf_pixel_range = 8.0;",
		"group_uniforms Animation;",
		"uniform float progress      : hint_range(-1.0, 1.0) = 0.0;",
		"uniform float intro_stagger : hint_range(0.01, 0.99) = 0.0;",
		"uniform float outro_stagger : hint_range(0.01, 0.99) = 0.0;",
	]
	if has_lnks: su.append("uniform float link_states_arr[%d];" % link_cap)
	if _uses_fx_clock:
		su.append("uniform float fx_time = 0.0;")
	out.append("\n".join(su))

	# Glyph uniforms.
	var gu: PackedStringArray = [
		"group_uniforms Glyphs;",
		"uniform int   glyph_mask_arr[%d];" % arr_sz,
		"uniform float glyph_intro_t[%d];"  % arr_sz,
		"uniform float glyph_outro_t[%d];"  % arr_sz,
		"uniform float glyph_seed_arr[%d];" % arr_sz,
	]
	if has_lnks: gu.append("uniform int glyph_link_idx[%d];" % arr_sz)
	if need_geom:
		gu.append_array([
			"uniform vec2  glyph_origin_arr[%d];"    % arr_sz,
			"uniform vec2  glyph_size_arr[%d];"      % arr_sz,
			"uniform float glyph_font_size_arr[%d];" % arr_sz,
		])
	out.append("\n".join(gu))

	# Layer uniforms.
	var lu: PackedStringArray = [
		"group_uniforms Layers;",
		"uniform vec4  layer_color_arr[%d];"   % layer_sz,
		"uniform float layer_sd_bias_arr[%d];" % layer_sz,
		"uniform float layer_feather_arr[%d];" % layer_sz,
	]
	if need_dilation:
		lu.append("uniform float layer_radius_arr[%d];" % layer_sz)
	out.append("\n".join(lu))

	# Tag helpers (only if any tags contributed them).
	if not helpers.is_empty():
		out.append("\n".join(helpers))

	# Built-in functions (always included).
	out.append("float msdf_median(float r, float g, float b) { return max(min(r, g), min(max(r, g), b)); }")

	# Bitmap-font coverage dilation must live in the fragment body: the
	# TEXTURE built-in is not accessible inside user functions.
	#
	# Outline layers (sd_bias > 0): one strong dilated ring (+ faint haze).
	# Glow layers (radius > 0, no bias): stepped gradient rings — strongest
	# near the glyph, fading outward, uniform in every direction.
	var dilation_stmt := ""
	if need_dilation:
		var head := "\n\tif (!msdf_enabled) {" if not has_imgs else "\n\tif (is_text && !msdf_enabled) {"
		dilation_stmt = head + """
		int   layer_index = layer * %d + glyph;
		float radius_px   = layer_radius_arr[layer_index];
		if (radius_px > 0.0) {
			vec2  texel = TEXTURE_PIXEL_SIZE;
			float acc   = tex.a;
			float feather = layer_feather_arr[layer_index];
			float w     = clamp(feather, 0.02, 1.0);
			float is_out = layer_sd_bias_arr[layer_index] > 0.0 ? 1.0 : 0.0;
			vec2 d0 = vec2(1.0, 0.0);  vec2 d1 = vec2(-1.0, 0.0);
			vec2 d2 = vec2(0.0, 1.0);  vec2 d3 = vec2(0.0, -1.0);
			vec2 d4 = vec2(0.7071068, 0.7071068);   vec2 d5 = vec2(-0.7071068, 0.7071068);
			vec2 d6 = vec2(0.7071068, -0.7071068);  vec2 d7 = vec2(-0.7071068, -0.7071068);
			for (int i = 0; i < 8; i++) {
				vec2 dv = (i == 0 ? d0 : i == 1 ? d1 : i == 2 ? d2 : i == 3 ? d3 :
					i == 4 ? d4 : i == 5 ? d5 : i == 6 ? d6 : d7) * texel;
				if (is_out > 0.5) {
					acc = max(acc, texture(TEXTURE, UV + dv * radius_px).a);
					vec2 o2 = dv * (radius_px + feather * radius_px + 1.0);
					acc = max(acc, texture(TEXTURE, UV + o2).a * w);
				} else {
					acc = max(acc, texture(TEXTURE, UV + dv * radius_px * 0.40).a * w);
					acc = max(acc, texture(TEXTURE, UV + dv * radius_px * 0.70).a * w * 0.62);
					acc = max(acc, texture(TEXTURE, UV + dv * radius_px).a * w * 0.34);
					vec2 o2 = dv * (radius_px * 1.35 + 1.0);
					acc = max(acc, texture(TEXTURE, UV + o2).a * w * 0.12);
				}
			}
			c.a *= acc;
		}
	}""" % arr_sz

	out.append("""void get_text_color(inout vec4 c, int glyph, vec4 tex, vec2 texture_pixel_size, vec2 uv, int layer) {
	int   layer_index     = layer * %d + glyph;
	vec4  base_color      = layer_color_arr[layer_index];
	if (msdf_enabled) {
		// MSDF RGB channels are distance data, not color — multiplying them
		// into the output produces dark fringed edges. Emit the flat layer
		// color and derive coverage from the SDF median instead.
		float sd              = msdf_median(tex.r, tex.g, tex.b);
		vec2  unit_range      = vec2(msdf_pixel_range) * texture_pixel_size;
		float screen_px_range = max(1.0, dot(unit_range, vec2(1.0) / fwidth(uv)));
		float sd_bias         = layer_sd_bias_arr[layer_index];
		float feather         = layer_feather_arr[layer_index];
		float alpha;
		if (feather > 0.0) {
			// Glow-style gradient: solid through the core, then an eased
			// falloff across the feather width instead of a hard rim.
			float d = 0.5 - sd;
			float t = clamp((d - sd_bias) / max(feather, 0.0001), 0.0, 1.0);
			alpha = pow(1.0 - t, 1.8);
		} else {
			alpha = clamp(screen_px_range * (sd - 0.5 + sd_bias) + 0.5, 0.0, 1.0);
		}
		c = vec4(base_color.rgb, base_color.a * alpha);
	} else {
		c = tex * base_color;
	}
}""" % arr_sz)

	# Vertex function — always emitted: it transfers glyph identity to the
	# fragment stage via rl_xfer, even when no tag contributes vertex code.
	out.append("""void vertex() {
	vec2 v = VERTEX;
	rl_xfer = vec2(clamp(COLOR.r, 0.0, 1.0), clamp(COLOR.g, 0.0, 1.0));
	%s
	%s
	%s
	VERTEX = v;
}""" % [common_vars, geom_vars, "\n\t".join(vert_calls)])

	# Fragment function.
	var get_color  := "get_text_color(c, glyph, tex, TEXTURE_PIXEL_SIZE, UV, layer);"
	var color_stmt := ("if (is_text) { %s } else { c = tex; }" % get_color) if has_imgs else get_color
	var frag_body  := ("\n\t" + "\n\t".join(PackedStringArray(frag_calls))) if frag_calls else ""
	# MSDF glow: dilate the distance field itself with a tap kernel (max over
	# neighbors minus their offset, in SDF units) so the halo can extend well
	# beyond the atlas' own distance band — one pass, no extra draws.
	var glow_stmt := ""
	if need_glow:
		var glow_head := "\n\tif (msdf_enabled) {" if not has_imgs else "\n\tif (is_text && msdf_enabled) {"
		glow_stmt = glow_head + """
		int   layer_index = layer * %d + glyph;
		float reach     = layer_radius_arr[layer_index];
		float feather_l = layer_feather_arr[layer_index];
		if (reach > 0.0 && feather_l > 0.0 && layer_sd_bias_arr[layer_index] <= 0.0) {
			float range_px = max(1.0, msdf_pixel_range);
			vec4  bc       = layer_color_arr[layer_index];
			float sd       = msdf_median(tex.r, tex.g, tex.b);
			vec2 d0 = vec2(1.0, 0.0);  vec2 d1 = vec2(-1.0, 0.0);
			vec2 d2 = vec2(0.0, 1.0);  vec2 d3 = vec2(0.0, -1.0);
			vec2 d4 = vec2(0.7071068, 0.7071068);   vec2 d5 = vec2(-0.7071068, 0.7071068);
			vec2 d6 = vec2(0.7071068, -0.7071068);  vec2 d7 = vec2(-0.7071068, -0.7071068);
			for (int i = 0; i < 8; i++) {
				vec2 dv = (i == 0 ? d0 : i == 1 ? d1 : i == 2 ? d2 : i == 3 ? d3 :
					i == 4 ? d4 : i == 5 ? d5 : i == 6 ? d6 : d7) * TEXTURE_PIXEL_SIZE;
				vec3 s0 = texture(TEXTURE, UV + dv * 0.40 * reach).rgb;
				sd = max(sd, msdf_median(s0.r, s0.g, s0.b) - 0.40 * reach / range_px);
				vec3 s1 = texture(TEXTURE, UV + dv * 0.70 * reach).rgb;
				sd = max(sd, msdf_median(s1.r, s1.g, s1.b) - 0.70 * reach / range_px);
				vec3 s2 = texture(TEXTURE, UV + dv * reach).rgb;
				sd = max(sd, msdf_median(s2.r, s2.g, s2.b) - reach / range_px);
			}
			float t = clamp((0.5 - sd) / max(feather_l, 0.0001), 0.0, 1.0);
			c.a = bc.a * pow(1.0 - t, 1.8);
		}
	}""" % arr_sz

	out.append("""void fragment() {
	%s
	vec4 tex = texture(TEXTURE, UV);
	vec4 c;
	%s%s%s%s
	COLOR = c;
}""" % [common_vars, color_stmt, dilation_stmt, glow_stmt, frag_body])

	# Uniform budget sanity check.
	var uni_bytes := arr_sz * 16 \
		+ (arr_sz * 20 if need_geom else 0) \
		+ layer_sz * 24 \
		+ (link_cap * 4 if has_lnks else 0)
	if _total_glyphs > max_arr or _total_glyphs * _total_layers > max_arr or uni_bytes > max_arr * 16:
		push_warning("RichLabel: uniform budget exceeded (~%d KB for %d glyphs × %d layers). Text beyond the limit will render incorrectly; consider splitting it across labels." % [uni_bytes / 1024, _total_glyphs, _total_layers])

	return "\n\n".join(PackedStringArray(out))

static func _get_max_array_size() -> int:
	var rd := RenderingServer.get_rendering_device()
	if not rd:
		# Compatibility mode: Usually 4096 floats
		return 4096
	var max_bytes = rd.limit_get(RenderingDevice.LIMIT_MAX_UNIFORM_BUFFER_SIZE)
	return max_bytes / 16

func _get_property_list() -> Array[Dictionary]:
	return PropList.start()\
		.category("Animation")\
			.pFloat("progress", -1.0, 1.0, 0.01, "time")\
			.pBool("pause_on_punctuation")\
			.pFloat("punctuation_pause", 0.0, 3.0, 0.01)\
			.pBool("pause_on_newline")\
			.pFloat("newline_pause", 0.0, 3.0, 0.01)\
		.group("Intro", "anim_intro_")\
			.pEnum("anim_intro_mode", StaggerMode)\
			.pFloat("anim_intro_stagger", 0.0, 0.98, 0.001)\
			.pFloat("anim_intro_duration")\
			.pEnum("anim_intro_tween", PropList.TransitionType)\
			.pEnum("anim_intro_ease", PropList.EaseType)\
		.group("Outro", "anim_outro_")\
			.pEnum("anim_outro_mode", StaggerMode)\
			.pFloat("anim_outro_stagger", 0.0, 0.98, 0.001)\
			.pFloat("anim_outro_duration")\
			.pEnum("anim_outro_tween", PropList.TransitionType)\
			.pEnum("anim_outro_ease", PropList.EaseType)\
		.category("Layout")\
			.pEnum("vertical_alignment", PropList.VerticalAlignment)\
			.pEnum("horizontal_alignment", PropList.HorizontalAlignment)\
			.pBool("autowrap")\
			.pFloat("char_spacing", -8.0, 32.0, 0.1, "px")\
			.pFloat("line_spacing", -8.0, 64.0, 0.1, "px")\
		.end()

class LayoutItem extends RefCounted:
	var kind := ItemKind.GLYPH
	var align := AlignMode.LEFT
	var position := Vector2.ZERO
	var size := Vector2.ZERO
	var baseline := Vector2.ZERO
	var advance := 0.0
	var tags: Array[RichTag] = []
	var index: int = 0
	var sequence_index := 0
	var line_index := 0
	var word_index := 0
	var intro_t := 0.0
	var outro_t := 0.0
	var shader_idx := -1
	var link_index := -1
	var link_meta: Variant = null

class Glyph extends LayoutItem:
	var character := ""
	var font: Font
	var font_size := 24
	var seed := 0.0
	var fill_color := Color.WHITE
	var layer_count := 1
	## Shaped advance (kerning-aware) in px, or -1.0 to measure naively.
	var advance_override := -1.0
	var layer_colors: PackedColorArray
	var layer_sd_bias: PackedFloat32Array
	var layer_offsets: PackedVector2Array
	var layer_seeds: PackedFloat32Array
	var layer_feathers: PackedFloat32Array
	## Bitmap-font coverage-dilation radius in pixels per layer (0 = off).
	var layer_radius: PackedFloat32Array
	var font_variation_params: Dictionary = {}
	var _font_variation_cache: Font = null

class InlineItem extends LayoutItem:
	var asset_id := ""
	var texture: Texture2D
	var scene_node: CanvasItem
	## Markup attributes from ~id w=64 fit=line valign=top etc.
	var attrs: Dictionary = {}
	## Vertical placement within the line: baseline (default) | top | center | bottom.
	var valign := "baseline"

class LayoutLine extends RefCounted:
	var items: Array[LayoutItem] = []
	var width := 0.0
	var ascent := 0.0
	var descent := 0.0
	var index := 0
