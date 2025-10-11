# filepath: /Users/lopa/test/scenes/scripts/ui/ActionHintLabel.gd
extends Label
class_name ActionHintLabel

@export var action_name: String = "interact"
@export var kb_template: String = "Press {key}"
@export var pad_template: String = "Press {key}"
@export var kb_font_size: int = 26
@export var pad_font_size: int = 30
@export var kb_font: Font
@export var pad_font: Font

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_text_and_font()
	var idm := InputDeviceManager.get_or_null()
	if idm and not idm.device_changed.is_connected(_on_device_changed):
		idm.device_changed.connect(_on_device_changed)

func _on_device_changed(is_controller: bool, _name: String) -> void:
	_update_text_and_font()

func _update_text_and_font() -> void:
	var idm := InputDeviceManager.get_or_null()
	var use_pad: bool = idm and idm.get("_is_controller_active")
	var tpl := pad_template if use_pad else kb_template
	text = InputDeviceManager.format_action(action_name, tpl)
	# Apply font and size overrides
	var size := pad_font_size if use_pad else kb_font_size
	add_theme_font_size_override("font_size", size)
	if use_pad and pad_font:
		add_theme_font_override("font", pad_font)
	elif not use_pad and kb_font:
		add_theme_font_override("font", kb_font)
