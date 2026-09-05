@tool
extends EditorPlugin

const LABEL_SCRIPT := preload("res://addons/rich_label/rich_label.gd")

## User-facing asset folders, shown under Project Settings > General > rich_text.
const DIR_SETTINGS := {
	"rich_text/fonts_dir": "res://assets/fonts",
	"rich_text/images_dir": "res://assets/images",
	"rich_text/scenes_dir": "res://assets/scenes",
}

func _enter_tree() -> void:
	add_custom_type("RichLabel", "Control", LABEL_SCRIPT, EditorInterface.get_base_control().get_theme_icon("RichTextLabel", "EditorIcons"))
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
