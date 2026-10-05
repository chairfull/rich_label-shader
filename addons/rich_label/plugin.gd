@tool
extends EditorPlugin

const LABEL_SCRIPT := preload("res://addons/rich_label/rich_label.gd")

## User-facing asset folders, shown under Project Settings > General > rich_text.
const DIR_SETTINGS := {
	"rich_text/fonts_dir": "res://assets/fonts",
	"rich_text/images_dir": "res://assets/images",
	"rich_text/scenes_dir": "res://assets/scenes",
}

var _tweaker_dock: Control

func _enter_tree() -> void:
	add_custom_type("RichLabel", "Control", LABEL_SCRIPT, EditorInterface.get_base_control().get_theme_icon("RichTextLabel", "EditorIcons"))
	_tweaker_dock = preload("res://addons/rich_label/tag_tweaker.gd").new()
	_tweaker_dock.name = "Tag Tweaker"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _tweaker_dock)
	for key: String in DIR_SETTINGS:
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, DIR_SETTINGS[key])
		# Register unconditionally: without property info the Project Settings
		# dialog treats the key as unknown and hides it.
		var info := {
			name = key,
			type = TYPE_STRING,
			hint = PROPERTY_HINT_PLACEHOLDER_TEXT,
			hint_string = DIR_SETTINGS[key],
		}
		ProjectSettings.add_property_info(info)
		ProjectSettings.set_initial_value(key, DIR_SETTINGS[key])

func _exit_tree() -> void:
	remove_custom_type("RichLabel")
	if _tweaker_dock:
		remove_control_from_docks(_tweaker_dock)
		_tweaker_dock.queue_free()
