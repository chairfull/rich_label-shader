@tool
class_name RTUtils

const LOWER_CASE := "abcdefghijklmnopqrstuvexyz"
const UPPER_CASE := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const NUMBERS := "0.123456789"
const LETTERS := LOWER_CASE + UPPER_CASE
const ALPHANUMERICS := LETTERS + NUMBERS

## Built-in tag scripts ship with the addon and are not user-configurable.
const TAGS_DIR := "res://addons/rich_label/rl_tags"
const TAG_EXT := "gd"

## User asset folders, overridable via Project Settings
## (rich_text/fonts_dir, rich_text/images_dir, rich_text/scenes_dir).
const FONT_EXTS: Array[String] = ["ttf", "otf", "fnt", "woff", "woff2"]
const IMAGE_EXTS: Array[String] = ["png", "webp", "jpg", "jpeg", "svg"]
const SCENE_EXTS: Array[String] = ["tscn", "scn"]

const DEFAULT_FONTS_DIR := "res://assets/fonts"
const DEFAULT_IMAGES_DIR := "res://assets/images"
const DEFAULT_SCENES_DIR := "res://assets/scenes"

## Synthetic stroke strength for [b]'s faux bold (FontVariation.variation_embolden).
const FAUX_BOLD_EMBOLDEN := 0.1
## Shear factor for [i]'s faux italic (FontVariation.variation_slant).
const FAUX_ITALIC_SLANT := 0.22

static var _dir_cache: Dictionary[String, Dictionary] = {}

static func is_id_char(ch: String) -> bool:
	return ch == "_" or ch in ALPHANUMERICS

static func is_id_start(ch: String) -> bool:
	return ch == "_" or ch in LETTERS

static func is_wrapped_string(s: String) -> bool:
	return is_wrapped(s, '"', '"') or is_wrapped(s, "'", "'")

static func is_wrapped(s: String, head := '"', tail := '"') -> bool:
	return s.begins_with(head) and s.ends_with(tail)

static func is_boundary(ch: String) -> bool:
	return is_whitespace(ch) or ch in ".,!?;:)]}>/\\\"'"

static func is_whitespace(ch: String) -> bool:
	return ch in " \t\n\r"

static func trim(s: String, head := '"', tail := '"') -> String:
	return s.trim_prefix(head).trim_suffix(tail)

static func trim_string_wrap(s: String) -> String:
	if is_wrapped(s, '"', '"'): return trim(s, '"', '"')
	if is_wrapped(s, "'", "'"): return trim(s, "'", "'")
	return s

static func sub(s: String, a := 0, b := 0) -> String:
	return s.substr(a, s.length() - a - b)

static func try_call(what: Variant, meth: StringName, default: Variant = null, ...args) -> Variant:
	if what is Object:
		var obj := what as Object
		if obj.has_method(meth):
			return obj.callv(meth, args)
	return default

static func packedString(asize: int, fill := "") -> PackedStringArray:
	var arr := PackedStringArray(); arr.resize(asize); arr.fill(fill); return arr

static func packedFloat32(asize: int, fill := 0.0) -> PackedFloat32Array:
	var arr := PackedFloat32Array(); arr.resize(asize); arr.fill(fill); return arr

static func packedFloat64(asize: int, fill := 0.0) -> PackedFloat64Array:
	var arr := PackedFloat64Array(); arr.resize(asize); arr.fill(fill); return arr

static func packedVec2(asize: int, fill := Vector2.ZERO) -> PackedVector2Array:
	var arr := PackedVector2Array(); arr.resize(asize); arr.fill(fill); return arr

static func packedVec3(asize: int, fill := Vector3.ZERO) -> PackedVector3Array:
	var arr := PackedVector3Array(); arr.resize(asize); arr.fill(fill); return arr

static func packedColor(asize: int, fill := Color.TRANSPARENT) -> PackedColorArray:
	var arr := PackedColorArray(); arr.resize(asize); arr.fill(fill); return arr

static func packedInt32(asize: int, fill := 0) -> PackedInt32Array:
	var arr := PackedInt32Array(); arr.resize(asize); arr.fill(fill); return arr

static func packedInt64(asize: int, fill := 0) -> PackedInt64Array:
	var arr := PackedInt64Array(); arr.resize(asize); arr.fill(fill); return arr

## RGB → HSV. h/s/v in 0..1 (h as fraction of a full turn).
static func rgb_to_hsv(c: Color) -> Vector3:
	var r := c.r
	var g := c.g
	var b := c.b
	var mx := maxf(r, maxf(g, b))
	var mn := minf(r, minf(g, b))
	var d := mx - mn
	var h := 0.0
	if d > 0.000001:
		if mx == r:
			h = fposmod((g - b) / d, 6.0)
		elif mx == g:
			h = (b - r) / d + 2.0
		else:
			h = (r - g) / d + 4.0
		h /= 6.0
	var s := 0.0 if mx <= 0.000001 else d / mx
	return Vector3(h, s, mx)

## Lerp the fill toward white (value < 0) or black (value > 0), then apply an
## optional hue rotation. Shared by the default outline/glow SHIFTED modes.
static func shift_color(fill: Color, value: float, hue_shift_deg: float) -> Color:
	value = clampf(value, -1.0, 1.0)
	var c := fill
	if value < 0.0:
		c = fill.lerp(Color.WHITE, -value)
	elif value > 0.0:
		c = fill.lerp(Color.BLACK, value)
	if absf(hue_shift_deg) > 0.001:
		var hsv := rgb_to_hsv(c)
		c = Color.from_hsv(fposmod(hsv.x + hue_shift_deg / 360.0, 1.0), hsv.y, hsv.z, c.a)
	return Color(c.r, c.g, c.b, fill.a)

#region Asset resolution

## Drops cached directory listings. RichLabel clears this on rebuilds inside the
## editor so newly added assets are picked up; at runtime the cache stays warm.
static func clear_cache() -> void:
	_dir_cache.clear()

static func fonts_dir() -> String:
	return _dir_setting("rich_text/fonts_dir", DEFAULT_FONTS_DIR)

static func images_dir() -> String:
	return _dir_setting("rich_text/images_dir", DEFAULT_IMAGES_DIR)

static func scenes_dir() -> String:
	return _dir_setting("rich_text/scenes_dir", DEFAULT_SCENES_DIR)

static func _dir_setting(key: String, fallback: String) -> String:
	if ProjectSettings.has_setting(key):
		var v: Variant = ProjectSettings.get_setting(key)
		if v is String and not (v as String).strip_edges().is_empty():
			return (v as String).strip_edges()
	return fallback

static func _listing(dir: String) -> Dictionary:
	if _dir_cache.has(dir):
		return _dir_cache[dir]
	var out: Dictionary = {}
	var da := DirAccess.open(dir)
	if da:
		da.list_dir_begin()
		var fname := da.get_next()
		while fname != "":
			if not da.current_is_dir():
				out[fname] = true
			fname = da.get_next()
		da.list_dir_end()
	_dir_cache[dir] = out
	return out

static func _find_file(dir: String, id: StringName, exts: Array[String]) -> String:
	var ls := _listing(dir)
	for ext in exts:
		var fname := "%s.%s" % [id, ext]
		if ls.has(fname):
			return dir.path_join(fname)
	return ""

static func gd_script_exists(id: StringName) -> bool:
	return FileAccess.file_exists(TAGS_DIR.path_join("%s.%s" % [id, TAG_EXT]))

static func get_gd_script(id: StringName) -> GDScript:
	var path := TAGS_DIR.path_join("%s.%s" % [id, TAG_EXT])
	if not FileAccess.file_exists(path):
		return null
	return load(path) as GDScript

static func scene_exists(id: StringName) -> bool:
	return _find_file(scenes_dir(), id, SCENE_EXTS) != ""

static func get_scene(id: StringName) -> Node:
	var path := _find_file(scenes_dir(), id, SCENE_EXTS)
	if path == "":
		return null
	var pcked: PackedScene = load(path)
	if pcked == null:
		push_warning("RTUtils: failed to load scene '%s'" % path)
		return null
	return pcked.instantiate()

static func font_exists(id: StringName) -> bool:
	return _find_file(fonts_dir(), id, FONT_EXTS) != ""

static func get_font(id: StringName) -> Font:
	var path := _find_file(fonts_dir(), id, FONT_EXTS)
	if path == "":
		return null
	return load(path) as Font

static func texture_exists(id: StringName) -> bool:
	return _find_file(images_dir(), id, IMAGE_EXTS) != ""

static func get_texture(id: StringName) -> Texture2D:
	var path := _find_file(images_dir(), id, IMAGE_EXTS)
	if path == "":
		return null
	return load(path) as Texture2D

#endregion
