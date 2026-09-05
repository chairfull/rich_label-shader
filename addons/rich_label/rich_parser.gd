@tool
class_name RichParser
extends RefCounted

#region Public types

## A single markup tag parsed from the source text, e.g. [fade speed=2 0.5].
class ParsedTag extends RefCounted:
	var name: StringName = &""
	var args: Array = []
	var kwargs: Dictionary = {}
	## True when the directive matched something known (tag script, color,
	## layout shorthand, link…). Unknown directives degrade to literal text
	## when their span is never explicitly closed.
	var known: bool = false


## Accumulated style state at a point in the text.
##
## Sentinel values mean "not explicitly set by any directive":
##   color / outline_color  — NO_COLOR  (Color(0,0,0,0))
##   font_size              — -1
##   font_scale             — -1.0
##   font_asset / align     — ""
##   outline_size           — -1
##   effect_strength / _speed — -1.0
##   link_meta              — null   (disambiguated by has_link_meta)
##
## Callers that need a fully-resolved style (not a delta) should seed the root
## ParsedStyle with their own defaults before calling parse_text().
class ParsedStyle extends RefCounted:
	const NO_COLOR := Color(0.0, 0.0, 0.0, 0.0)

	var color: Color = NO_COLOR
	var bold: bool = false
	var italic: bool = false
	var underline: bool = false
	var align: String = ""
	var font_size: int = -1
	var font_scale: float = -1.0
	var font_asset: String = ""
	var link_meta: Variant = null
	var has_link_meta: bool = false
	var outline_size: int = -1
	var outline_color: Color = NO_COLOR
	var effect_strength: float = -1.0
	var effect_speed: float = -1.0
	var tags: Array[ParsedTag] = []

	## Returns a shallow copy. Tags array is duplicated (tags themselves are not).
	func duplicate() -> ParsedStyle:
		var c := ParsedStyle.new()
		c.color = color
		c.bold = bold
		c.italic = italic
		c.underline = underline
		c.align = align
		c.font_size = font_size
		c.font_scale = font_scale
		c.font_asset = font_asset
		c.link_meta = link_meta
		c.has_link_meta = has_link_meta
		c.outline_size = outline_size
		c.outline_color = outline_color
		c.effect_strength = effect_strength
		c.effect_speed = effect_speed
		c.tags = tags.duplicate()
		return c

	## Returns a new ParsedStyle with delta applied on top of self.
	## Boolean flags are additive (once true, stay true).
	## Sentinel values in delta are skipped (base value is kept).
	## Tags from both are concatenated.
	func merge(delta: ParsedStyle) -> ParsedStyle:
		var m := duplicate()
		if delta.color        != NO_COLOR:  m.color        = delta.color
		if delta.bold:                      m.bold         = true
		if delta.italic:                    m.italic       = true
		if delta.underline:                 m.underline    = true
		if delta.align        != "":        m.align        = delta.align
		if delta.font_size    >= 0:         m.font_size    = delta.font_size
		if delta.font_scale   >= 0.0:       m.font_scale   = delta.font_scale
		if delta.font_asset   != "":        m.font_asset   = delta.font_asset
		if delta.has_link_meta:
			m.link_meta     = delta.link_meta
			m.has_link_meta = true
		if delta.outline_size  >= 0:        m.outline_size  = delta.outline_size
		if delta.outline_color != NO_COLOR: m.outline_color = delta.outline_color
		if delta.effect_strength >= 0.0:    m.effect_strength = delta.effect_strength
		if delta.effect_speed    >= 0.0:    m.effect_speed    = delta.effect_speed
		m.tags = tags.duplicate()
		m.tags.append_array(delta.tags)
		return m

	## Field-wise equality, used to merge adjacent text segments with equal style.
	func style_equals(other: ParsedStyle) -> bool:
		if color        != other.color        : return false
		if bold         != other.bold         : return false
		if italic       != other.italic       : return false
		if underline    != other.underline    : return false
		if align        != other.align        : return false
		if font_size    != other.font_size    : return false
		if font_scale   != other.font_scale   : return false
		if font_asset   != other.font_asset   : return false
		if has_link_meta != other.has_link_meta: return false
		if link_meta    != other.link_meta    : return false
		if outline_size != other.outline_size : return false
		if outline_color != other.outline_color: return false
		if not is_equal_approx(effect_strength, other.effect_strength): return false
		if not is_equal_approx(effect_speed,    other.effect_speed)   : return false
		return _tags_equal(tags, other.tags)

	## True when this style delta actually changes something the renderer
	## understands (used to decide whether an unclosed span should auto-close).
	func is_meaningful() -> bool:
		if color != NO_COLOR or bold or italic or underline: return true
		if align != "" or has_link_meta:                    return true
		if font_size >= 0 or font_scale >= 0.0:             return true
		if font_asset != "":                                return true
		if outline_size >= 0 or outline_color != NO_COLOR:  return true
		if effect_strength >= 0.0 or effect_speed >= 0.0:   return true
		for t in tags:
			if t.known:
				return true
		return false

	## Returns a Dictionary of all non-sentinel fields, suitable for duck-typing
	## property injection (e.g. setting matching props on a RichTag instance).
	func to_props() -> Dictionary:
		var d: Dictionary = {}
		if color         != NO_COLOR:  d[&"color"]           = color
		if bold:                       d[&"bold"]            = bold
		if italic:                     d[&"italic"]          = italic
		if underline:                  d[&"underline"]       = underline
		if align         != "":        d[&"align"]           = align
		if font_size     >= 0:         d[&"font_size"]       = font_size
		if font_scale    >= 0.0:       d[&"font_scale"]      = font_scale
		if font_asset    != "":        d[&"font_asset"]      = font_asset
		if has_link_meta:              d[&"link_meta"]       = link_meta
		if outline_size  >= 0:         d[&"outline_size"]    = outline_size
		if outline_color != NO_COLOR:  d[&"outline_color"]   = outline_color
		if effect_strength >= 0.0:     d[&"effect_strength"] = effect_strength
		if effect_speed    >= 0.0:     d[&"effect_speed"]    = effect_speed
		return d

	static func _tags_equal(a: Array[ParsedTag], b: Array[ParsedTag]) -> bool:
		if a.size() != b.size():
			return false
		for i in a.size():
			if a[i].name != b[i].name or a[i].args != b[i].args or a[i].kwargs != b[i].kwargs:
				return false
		return true


## A single output unit from the parser — either a text run or an inline asset.
class ParsedSegment extends RefCounted:
	var kind: StringName = &"text"  ## &"text" or &"asset"
	var text: String = ""
	var asset_id: String = ""
	var asset_type: String = ""     ## "image" or "scene" (only when kind == &"asset")
	var attrs: Dictionary = {}      ## inline asset attributes (~id w=64 fit=line)
	var style: ParsedStyle          ## style active over this segment

#endregion

#region Private result types

class _ParseResult extends RefCounted:
	var segments: Array[ParsedSegment] = []
	var index: int = 0
	var closed: bool = false

class _BracedResult extends RefCounted:
	var found: bool = false
	var text: String = ""
	var index: int = 0

#endregion

#region Public API

## Parse [i]source[/i] and return a flat list of segments.
## [i]default_style[/i] seeds the root style state (colour, effect params, etc.).
## [i]context[/i] is used to resolve [code]$variable[/code] and [code]{expr}[/code] references.
static func parse_text(source: String, default_style: ParsedStyle, context: Object) -> Array[ParsedSegment]:
	var normalized := source.replace("\r\n", "\n").replace("\r", "\n")
	return _parse_sequence(normalized, 0, default_style, context, "").segments

#endregion

# ── Core recursive descent parser ─────────────────────────────────────────────

static func _parse_sequence(
		source: String,
		start_index: int,
		style: ParsedStyle,
		context: Object,
		closing_marker: String) -> _ParseResult:

	var result := _ParseResult.new()
	var buffer := ""
	var index := start_index

	while index < source.length():
		# Closing marker check (e.g. "]" for bracket spans, "=" or "_" for inline).
		if closing_marker != "" and _matches_closer(source, index, closing_marker):
			_flush(result.segments, buffer, style)
			result.index = index + closing_marker.length()
			result.closed = true
			return result

		var ch := source[index]

		# ── Escape sequences: \[ \] \~ \$ \{ \backslash ─────────────────────
		if ch == "\\":
			if index + 1 < source.length() and source[index + 1] in "\\[]~${":
				buffer += source[index + 1]
				index += 2
				continue
			buffer += ch
			index += 1
			continue

		# ── Bracket tag: [directive...]text]  ──────────────────────────────
		if ch == "[":
			var header_end := source.find("]", index + 1)
			if header_end != -1:
				var header := source.substr(index + 1, header_end - index - 1)
				var delta := _parse_header(header)
				var next_style := style.merge(delta)
				var nested := _parse_sequence(source, header_end + 1, next_style, context, "]")
				# Adopt the span when it was explicitly closed by `]`, or when
				# the directive is recognized but never closed (tolerant EOF
				# auto-close). Unknown directives degrade to literal text.
				if nested.closed or delta.is_meaningful():
					_flush(result.segments, buffer, style)
					buffer = ""
					result.segments.append_array(nested.segments)
					index = nested.index
					continue

		# ── Inline markers: =bold= and _italic_  ──────────────────────────
		var matched := false
		for pair in [[&"=", &"bold"], [&"_", &"italic"]]:
			var marker := String(pair[0])
			if _can_open_inline(source, index, marker):
				var new_style := style.duplicate()
				if pair[1] == &"bold":   new_style.bold   = true
				else:                    new_style.italic = true
				var nested := _parse_sequence(source, index + 1, new_style, context, marker)
				# Inline markers always adopt: they only open after word
				# boundaries, so an unclosed one stays bold to the end.
				_flush(result.segments, buffer, style)
				buffer = ""
				result.segments.append_array(nested.segments)
				index = nested.index
				matched = true
				break
		if matched:
			continue

		# ── $variable reference  ───────────────────────────────────────────
		if ch == "$":
			var token := _read_token(source, index + 1, ".")
			if token != "":
				buffer += _stringify(_resolve_path(token, context))
				index += token.length() + 1
				continue

		# ── {expression} evaluation  ───────────────────────────────────────
		if ch == "{":
			var br := _read_braced_expression(source, index)
			if br.found:
				buffer += _stringify(_evaluate_expression(br.text, context))
				index = br.index
				continue

		# ── ~asset_id inline asset  ────────────────────────────────────────
		if ch == "~":
			var asset_token := _read_token(source, index + 1, ".-")
			if asset_token != "":
				var asset_type := _resolve_inline_asset(asset_token)
				if asset_type != "":
					var attrs := _read_asset_attrs(source, index + 1 + asset_token.length())
					var consumed := int(attrs.get("__end", index + 1 + asset_token.length()))
					attrs.erase("__end")
					_flush(result.segments, buffer, style)
					buffer = ""
					var seg := ParsedSegment.new()
					seg.kind = &"asset"
					seg.asset_id = asset_token
					seg.asset_type = asset_type
					seg.attrs = attrs
					seg.style = style.duplicate()
					result.segments.append(seg)
					index = consumed
					continue
			buffer += ch
			index += 1
			continue

		buffer += ch
		index += 1

	_flush(result.segments, buffer, style)
	result.index = index
	# Not explicitly closed. Callers decide whether to adopt the span
	# (tolerant EOF auto-close for recognized directives) or degrade it
	# to literal text.
	result.closed = false
	return result


# ── Segment helpers ───────────────────────────────────────────────────────────

## Appends [i]text[/i] to [i]segments[/i], merging into the previous segment
## when it is a text segment with an equal style (avoids unnecessary splits).
static func _flush(segments: Array[ParsedSegment], text: String, style: ParsedStyle) -> void:
	if text == "":
		return
	if not segments.is_empty():
		var last := segments[-1]
		if last.kind == &"text" and last.style.style_equals(style):
			last.text += text
			return
	var seg := ParsedSegment.new()
	seg.kind = &"text"
	seg.text = text
	seg.style = style.duplicate()
	segments.append(seg)


# ── Style/header parsing ──────────────────────────────────────────────────────

## Parses a bracket header (the text between "[" and "]") into a style delta.
## Multiple directives are separated by ";".
static func _parse_header(header: String) -> ParsedStyle:
	var delta := ParsedStyle.new()
	for raw in header.split(";"):
		var directive := raw.strip_edges()
		if directive != "":
			_apply_directive(delta, _parse_directive(directive))
	return delta


## Parses one directive string into a ParsedTag (name + positional args + kwargs).
static func _parse_directive(text: String) -> ParsedTag:
	var parts := text.split(" ", false)
	var tag := ParsedTag.new()
	tag.name = StringName(parts[0].strip_edges().to_lower()) if not parts.is_empty() else &""
	for i in range(1, parts.size()):
		var token := parts[i].strip_edges()
		if token == "":
			continue
		var eq := token.find("=")
		if eq != -1:
			tag.kwargs[token.substr(0, eq).strip_edges().to_lower()] = _parse_literal(token.substr(eq + 1).strip_edges())
		else:
			tag.args.append(_parse_literal(token))
	return tag


## Applies a parsed directive to [i]delta[/i], mutating it in place.
static func _apply_directive(delta: ParsedStyle, tag: ParsedTag) -> void:
	var name := String(tag.name)
	if name == "":
		return

	# Symbol-head shorthand: !name → TODO tag, etc.
	var first_char := name[0]
	if RichTag.SYMBOL_HEADS.has(first_char):
		var remainder := name.substr(1)
		if remainder:
			tag.args.insert(0, remainder)
		name = String(RichTag.SYMBOL_HEADS[first_char])
		tag.name = StringName(name)

	# Layout and typography shorthands.
	match name:
		"left", "right", "center", "fill":
			delta.align = name
			return
		"b", "bold":
			delta.bold = true
			return
		"i", "italic":
			delta.italic = true
			return
		"u", "underline":
			delta.underline = true
			return

	# Integer → absolute font size; float → relative scale.
	if name.is_valid_int():
		var sz := name.to_int()
		delta.font_size = sz
		delta.tags.append(_make_tag(&"size", [], {&"size": sz}))
		return
	if name.is_valid_float():
		var sc := name.to_float()
		delta.font_scale = sc
		delta.tags.append(_make_tag(&"size", [], {&"scale": sc}))
		return

	# Font asset shorthand: if the name maps to a known font, treat it as one.
	if RTUtils.font_exists(name):
		delta.font_asset = name
		return

	# Named tag script.
	if RTUtils.gd_script_exists(name):
		tag.known = true
		delta.tags.append(tag)
		_apply_kwargs_to_style(delta, tag.kwargs)
		return

	# Link shorthand: [=some_id] — first occurrence wins within a header.
	if name.begins_with("=") and not delta.has_link_meta:
		delta.link_meta = name.substr(1)
		delta.has_link_meta = true
		return

	# Color name → auto-tint.
	var col := _parse_color(name)
	if col != ParsedStyle.NO_COLOR:
		var tint := _make_tag(&"tint", [], {&"color": name})
		tint.known = true
		delta.tags.append(tint)
		delta.color = col
		return

	# Unknown directive — register as a generic tag.
	delta.tags.append(tag)
	_apply_kwargs_to_style(delta, tag.kwargs)


static func _apply_kwargs_to_style(style: ParsedStyle, kwargs: Dictionary) -> void:
	if kwargs.has("color"):
		var c := _parse_color(String(kwargs.get("color", "")))
		if c != ParsedStyle.NO_COLOR:
			style.color = c
	if kwargs.has("outline") or kwargs.has("outline_size"):
		style.outline_size = max(0, int(roundf(float(kwargs.get("outline_size", kwargs.get("outline", 0))))))
	if kwargs.has("outline_color"):
		var oc := _parse_color(String(kwargs.get("outline_color", "")))
		if oc != ParsedStyle.NO_COLOR:
			style.outline_color = oc
	if kwargs.has("strength") or kwargs.has("amp"):
		style.effect_strength = max(0.0, float(kwargs.get("strength", kwargs.get("amp", 1.0))))
	if kwargs.has("speed"):
		style.effect_speed = max(0.01, float(kwargs.get("speed", 1.0)))


# ── Tag construction helpers ──────────────────────────────────────────────────

static func _make_tag(name: StringName, args: Array, kwargs: Dictionary) -> ParsedTag:
	var t := ParsedTag.new()
	t.name = name
	t.args = args
	t.kwargs = kwargs
	return t


# ── String / expression utilities ─────────────────────────────────────────────

static func _parse_color(value: String) -> Color:
	var normalized := value.strip_edges().to_lower()
	if normalized == "":
		return ParsedStyle.NO_COLOR
	return Color.from_string(normalized, ParsedStyle.NO_COLOR)

static func _read_token(source: String, start: int, extra_chars := "") -> String:
	if start >= source.length() or not RTUtils.is_id_start(source[start]):
		return ""
	var i := start
	while i < source.length():
		var ch := source[i]
		if RTUtils.is_id_char(ch) or (extra_chars and ch in extra_chars):
			i += 1
		else:
			break
	return source.substr(start, i - start)

static func _resolve_inline_asset(asset_id: String) -> String:
	if RTUtils.texture_exists(asset_id): return "image"
	if RTUtils.scene_exists(asset_id): return "scene"
	return ""

static func _matches_closer(source: String, index: int, closing_marker: String) -> bool:
	if closing_marker == "":
		return false
	return _matches_at(source, index, closing_marker) \
		and (closing_marker == "]" or _can_close_inline(source, index, closing_marker))

static func _can_open_inline(source: String, index: int, marker: String) -> bool:
	if not _matches_at(source, index, marker):
		return false
	if index + marker.length() >= source.length():
		return false
	if RTUtils.is_whitespace(source[index + marker.length()]):
		return false
	if index == 0:
		return true
	return RTUtils.is_boundary(source[index - 1])

static func _can_close_inline(source: String, index: int, marker: String) -> bool:
	if index <= 0:
		return false
	if RTUtils.is_whitespace(source[index - 1]):
		return false
	var next := index + marker.length()
	if next >= source.length():
		return true
	return RTUtils.is_boundary(source[next])

static func _matches_at(source: String, index: int, marker: String) -> bool:
	if index < 0 or index + marker.length() > source.length():
		return false
	return source.substr(index, marker.length()) == marker

static func _read_braced_expression(source: String, start_index: int) -> _BracedResult:
	var result := _BracedResult.new()
	result.index = start_index
	var depth := 0
	var in_quote := ""
	var escaped := false
	for index in range(start_index, source.length()):
		var ch := source[index]
		if in_quote != "":
			if escaped:        escaped = false
			elif ch == "\\":   escaped = true
			elif ch == in_quote: in_quote = ""
			continue
		if ch == "\"" or ch == "'":
			in_quote = ch
			continue
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				result.found = true
				result.text = source.substr(start_index + 1, index - start_index - 1)
				result.index = index + 1
				return result
	return result

static func _evaluate_expression(code: String, context: Object, kwargs := {}) -> Variant:
	var expr := Expression.new()
	var err := expr.parse(code, kwargs.keys())
	if err != OK:
		push_warning("RichParser: expression parse failed: %s" % expr.get_error_text())
		return ""
	var result: Variant = expr.execute(kwargs.values(), context)
	if expr.has_execute_failed():
		push_warning("RichParser: expression execution failed: %s" % expr.get_error_text())
		return ""
	return result

static func _resolve_path(path: String, context: Object) -> Variant:
	if path in context:
		return context[path]
	var parts := path.split(".", false)
	if parts.is_empty():
		return ""
	var current: Variant = context.get(parts[0])
	if current == null:
		current = _read_member(context, parts[0])
	for i in range(1, parts.size()):
		current = _read_member(current, parts[i])
	return current

static func _read_member(value: Variant, key: String) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			return value.get(key, "")
		TYPE_ARRAY:
			if key.is_valid_int():
				var i := key.to_int()
				if i >= 0 and i < value.size():
					return value[i]
			return ""
		_:
			if value is Object:
				return value.get(key)
	return ""

static func _stringify(value: Variant) -> String:
	if value == null:        return ""
	if value is String:      return value
	if value is StringName:  return String(value)
	return str(value)

static func _parse_literal(token: String) -> Variant:
	var t := token.strip_edges()
	if t == "":
		return null
	# Bare words (e.g. color names like `black`) fail str_to_var; keep the raw
	# string so tag scripts receive something sensible.
	var v: Variant = str_to_var(t)
	if v == null and t != "null":
		return t
	return v

## Characters that terminate an inline asset attribute value. Note that `.`
## is deliberately absent so numeric values like `1.5` survive.
const _ATTR_VAL_STOP := " \t\n\r,!?:;)]}>\"'"

## Reads optional space-separated attributes after an inline asset id:
##   ~icon w=64 fit=none valign=top
## Returns the attribute dictionary plus a "__end" index (source position
## after the last consumed character).
static func _read_asset_attrs(source: String, start: int) -> Dictionary:
	var attrs: Dictionary = {}
	var pos := start
	while pos < source.length() and source[pos] == " ":
		var probe := pos + 1
		var key := _read_token(source, probe)
		if key == "":
			break
		var after := probe + key.length()
		var raw_val := ""
		if after < source.length() and source[after] == "=":
			var vs := after + 1
			var ve := vs
			while ve < source.length() and not (source[ve] in _ATTR_VAL_STOP):
				ve += 1
			raw_val = source.substr(vs, ve - vs)
			after = ve
		attrs[key] = _coerce_attr(raw_val)
		pos = after
	attrs["__end"] = pos
	return attrs

static func _coerce_attr(raw: String) -> Variant:
	if raw == "":
		return true
	if raw.is_valid_int():
		return raw.to_int()
	if raw.is_valid_float():
		return raw.to_float()
	if raw == "true":
		return true
	if raw == "false":
		return false
	return raw
