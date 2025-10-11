# filepath: /Users/lopa/test/scenes/scripts/core/InputDeviceManager.gd
extends Node

signal device_changed(is_controller: bool, device_name: String)

var _is_controller_active: bool = false
var is_controller_active: bool:
	set(value):
		_set_device(value, "controller" if value else "keyboard")
	get:
		return _is_controller_active

var last_device_name: String = "keyboard" # "keyboard" | "controller"

# Optional: always run to catch inputs even when paused/menus
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_set_device(true, "controller")
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventKey:
		_set_device(false, "keyboard")

func _set_device(use_controller: bool, name: String) -> void:
	if _is_controller_active == use_controller and last_device_name == name:
		return
	_is_controller_active = use_controller
	last_device_name = name
	emit_signal("device_changed", _is_controller_active, last_device_name)

static func get_or_null() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return null
	return tree.root.get_node_or_null("/root/InputDeviceManager")

# --- Action hint formatting helpers ---
static func get_action_hint(action: String) -> String:
	var idm := InputDeviceManager.get_or_null()
	var use_controller: bool = false
	if idm:
		# Access the autoload's property safely
		if idm.has_method("get"):
			var v = idm.get("_is_controller_active")
			if typeof(v) == TYPE_BOOL:
				use_controller = v
	var events := InputMap.action_get_events(action)
	if use_controller:
		# Prefer a joypad button hint
		for e in events:
			if e is InputEventJoypadButton:
				return _joy_button_name((e as InputEventJoypadButton).button_index)
			if e is InputEventJoypadMotion:
				return _joy_axis_name((e as InputEventJoypadMotion).axis)
		# Fallback generic
		return action.capitalize()
	# Keyboard/mouse
	for e in events:
		if e is InputEventKey:
			var key := (e as InputEventKey).physical_keycode
			return OS.get_keycode_string(key)
		if e is InputEventMouseButton:
			var mb := (e as InputEventMouseButton).button_index
			match mb:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				_: return "Mouse %d" % mb
	# Fallback
	return action.capitalize()

static func format_action(action: String, template: String = "{key}") -> String:
	var key := get_action_hint(action)
	return template.replace("{key}", key)

static func _joy_button_name(idx: int) -> String:
	match idx:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_BACK: return "Back"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_GUIDE: return "Guide"
		JOY_BUTTON_DPAD_UP: return "D↑"
		JOY_BUTTON_DPAD_DOWN: return "D↓"
		JOY_BUTTON_DPAD_LEFT: return "D←"
		JOY_BUTTON_DPAD_RIGHT: return "D→"
		_: return "Btn %d" % idx

static func _joy_axis_name(axis: int) -> String:
	match axis:
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return "LS"
		JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y: return "RS"
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
		_: return "Axis %d" % axis
