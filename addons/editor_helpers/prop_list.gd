@tool
class_name PropList extends RefCounted
# To be used w _get_property_list()

var _obj: Object
var _group: String
var _subgroup: String
var _list: Array[Dictionary]
var _for := false
var _for_range: int
var _for_autogroup: bool
var _for_head: String
var _for_list: Array[Dictionary]

enum StrType {
	DEFAULT,
	PLACEHOLDER,
	MULTILINE,
	MULTILINE_MONO,
	MULTILINE_MONO_NOWRAP,
	MULTILINE_NOWRAP,
	EXPRESSION,
}

enum TransitionType { LINEAR, SINE, QUINT, QUART, QUAD, EXPO, ELASTIC, CUBIC, CIRC, BOUNCE, BACK, SPRING }
enum EaseType { IN, OUT, IN_OUT, OUT_IN }
enum HorizontalAlignment { LEFT, CENTER, RIGHT, FILL } 
enum VerticalAlignment { TOP, CENTER, BOTTOM, FILL }

static func start(target: Object = null) -> PropList:
	var p := PropList.new()
	p._obj = target
	return p

func end() -> Array[Dictionary]:
	#print(JSON.stringify(_list, "\t", false))
	return _list

func _add(name: String, type: int, hint := 0, hint_string := "", usage := PROPERTY_USAGE_DEFAULT) -> PropList:
	(_for_list if _for else _list).append({ name=name, type=type, hint=hint, hint_string=hint_string, usage=usage })
	return self

func category(name: String) -> PropList:
	return _add(name, TYPE_NIL, -1, "", PROPERTY_USAGE_CATEGORY)

func group(name: String, prefix := "") -> PropList:
	if not prefix: prefix = name.to_lower() + "_"
	_group = prefix
	return _add(name, TYPE_NIL, 0, prefix, PROPERTY_USAGE_GROUP)

func subgroup(name: String, prefix := "") -> PropList:
	if not prefix: prefix = name.to_lower() + "_"
	_subgroup = prefix
	return _add(name, TYPE_NIL, 0, prefix, PROPERTY_USAGE_SUBGROUP)
	
func button(name: String, label := "") -> PropList:
	if not label:
		label = name
		if _group and label.begins_with(_group):
			label = label.trim_prefix(_group)
		if _subgroup and label.begins_with(_subgroup):
			label = label.trim_prefix(_subgroup)
		label = label.capitalize()
	return _add(name, TYPE_CALLABLE, PROPERTY_HINT_TOOL_BUTTON, label, PROPERTY_USAGE_EDITOR)

func pEnum(name: String, enumobj: Variant, suggestion := false) -> PropList:
	var h := PROPERTY_HINT_ENUM_SUGGESTION if suggestion else PROPERTY_HINT_ENUM
	var type := TYPE_NIL
	var options: Array[String]
	if enumobj is Dictionary:
		type = enumobj.get_typed_value_builtin()
		options.assign(enumobj.keys())
	elif typeof(enumobj) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		type = TYPE_STRING
		options.assign(enumobj)
	if suggestion and type == TYPE_NIL:
		type = TYPE_STRING
	if type == TYPE_INT or type == TYPE_NIL:
		type = TYPE_INT # In case it's TYPE_NIL.
		options.assign(options.map(func(x): return x.capitalize()))
	return _add(name, type, h, ",".join(options))

func pBool(name: String) -> PropList:
	return _add(name, TYPE_BOOL)

func pInt(name: String, from: Variant = null, to: Variant = null, step: Variant = null, suffix := "") -> PropList:
	if from is int and to is int:
		var hint := "%s,%s" % [from, to]
		if step is int: hint += ",%s" % step
		if suffix: hint += ",suffix:%s" % suffix
		return _add(name, TYPE_INT, PROPERTY_HINT_RANGE, hint)
	return _add(name, TYPE_INT)

func pFloat(name: String, from: Variant = null, to: Variant = null, step: Variant = null, suffix := "") -> PropList:
	if from is float and to is float:
		var hint := "%s,%s" % [from, to]
		if step is float: hint += ",%s" % step
		if suffix: hint += ",suffix:%s" % suffix
		return _add(name, TYPE_FLOAT, PROPERTY_HINT_RANGE, hint)
	return _add(name, TYPE_FLOAT)

func pRadius(name: String, step := TAU / 64.0) -> PropList:
	return pFloat(name, -PI, PI, step, "radians")

func pDegrees(name: String, step := 360.0 / 64.0) -> PropList:
	return pFloat(name, -180, 180, step, "degrees")

func pVector2(name: String) -> PropList:
	return _add(name, TYPE_VECTOR2)

func pVector3(name: String) -> PropList:
	return _add(name, TYPE_VECTOR3)

func pString(name: String, str_type := StrType.DEFAULT, placeholder := "") -> PropList:
	match str_type:
		StrType.DEFAULT: _add(name, TYPE_STRING)
		StrType.PLACEHOLDER: _add(name, TYPE_STRING, PROPERTY_HINT_PLACEHOLDER_TEXT, placeholder)
		StrType.MULTILINE: _add(name, TYPE_STRING, PROPERTY_HINT_MULTILINE_TEXT)
		StrType.MULTILINE_MONO: _add(name, TYPE_STRING, PROPERTY_HINT_MULTILINE_TEXT, "monospace")
		StrType.MULTILINE_MONO_NOWRAP: _add(name, TYPE_STRING, PROPERTY_HINT_MULTILINE_TEXT, "monospace no_wrap")
		StrType.MULTILINE_NOWRAP: _add(name, TYPE_STRING, PROPERTY_HINT_MULTILINE_TEXT, "no_wrap")
		StrType.EXPRESSION: _add(name, TYPE_STRING, PROPERTY_HINT_EXPRESSION)
	return self

func pStringName(name: String) -> PropList:
	return _add(name, TYPE_STRING_NAME)

func pColor(name: String = "color") -> PropList:
	return _add(name, TYPE_COLOR)

func forStart(range: int, head := "", autogroup := true) -> PropList:
	_for = true
	_for_autogroup = autogroup
	_for_range = range
	_for_head = head
	return self

func forEnd() -> PropList:
	_for = false
	for i in _for_range:
		if _for_autogroup:
			group("%s %s" % [_for_head.capitalize(), i], "%s_%s_" % [_for_head, i])
		for item in _for_list:
			if item.type != TYPE_NIL:
				var copy := item.duplicate()
				copy.name = "%s_%s_%s" % [_for_head, i, copy.name]
				_list.append(copy)
	_for_list.clear()
	return self
