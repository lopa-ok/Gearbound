extends Node
class_name ControllerSupport

static func _ensure_action(name: String) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name)

static func _add_button(action: String, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)

static func _remove_button(action: String, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	if InputMap.action_has_event(action, ev):
		InputMap.action_erase_event(action, ev)

static func _add_axis(action: String, axis: int, axis_value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = axis_value
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)

static func _add_key(action: String, physical_keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)

static func ensure_input_map() -> void:
	# Core UI navigation
	for a in ["ui_up","ui_down","ui_left","ui_right","ui_accept","ui_cancel"]:
		_ensure_action(a)
	# Game actions
	for a in ["interact","drop","switch_player","pause",
		"move_forward","move_back","move_left","move_right",
		"look_up","look_down","look_left","look_right"]:
		_ensure_action(a)
	# Also ensure actions used by HumanPlayer
	for a in ["forward","back","left","right","sprint","jump","unstuck"]:
		_ensure_action(a)
	# Face buttons
	_add_button("ui_accept", JOY_BUTTON_A)
	# Interact/Pickup: A only (prevent conflict with Jump on Square)
	_remove_button("interact", JOY_BUTTON_X)
	_add_button("interact", JOY_BUTTON_A)
	_add_button("ui_cancel", JOY_BUTTON_B)
	# Ensure X is not mapped to Drop to avoid conflicts
	_remove_button("drop", JOY_BUTTON_X)
	# Drop on Circle (B)
	_remove_button("drop", JOY_BUTTON_RIGHT_STICK)
	_add_button("drop", JOY_BUTTON_B)
	# Also bind keyboard 'O' to Drop
	_add_key("drop", KEY_O)
	# Switch player on Y
	_add_button("switch_player", JOY_BUTTON_Y)
	# Start -> pause
	_add_button("pause", JOY_BUTTON_START)
	# D-pad navigation
	_add_button("ui_up", JOY_BUTTON_DPAD_UP)
	_add_button("ui_down", JOY_BUTTON_DPAD_DOWN)
	_add_button("ui_left", JOY_BUTTON_DPAD_LEFT)
	_add_button("ui_right", JOY_BUTTON_DPAD_RIGHT)
	# Left stick -> movement (custom + ui_* + HumanPlayer actions)
	_add_axis("move_left", JOY_AXIS_LEFT_X, -0.5)
	_add_axis("move_right", JOY_AXIS_LEFT_X, 0.5)
	_add_axis("move_forward", JOY_AXIS_LEFT_Y, -0.5)
	_add_axis("move_back", JOY_AXIS_LEFT_Y, 0.5)
	_add_axis("ui_left", JOY_AXIS_LEFT_X, -0.5)
	_add_axis("ui_right", JOY_AXIS_LEFT_X, 0.5)
	_add_axis("ui_up", JOY_AXIS_LEFT_Y, -0.5)
	_add_axis("ui_down", JOY_AXIS_LEFT_Y, 0.5)
	_add_axis("left", JOY_AXIS_LEFT_X, -0.5)
	_add_axis("right", JOY_AXIS_LEFT_X, 0.5)
	_add_axis("forward", JOY_AXIS_LEFT_Y, -0.5)
	_add_axis("back", JOY_AXIS_LEFT_Y, 0.5)
	# Softer thresholds for gentle stick deflection
	_add_axis("left", JOY_AXIS_LEFT_X, -0.2)
	_add_axis("right", JOY_AXIS_LEFT_X, 0.2)
	_add_axis("forward", JOY_AXIS_LEFT_Y, -0.2)
	_add_axis("back", JOY_AXIS_LEFT_Y, 0.2)
	# Right stick -> look
	_add_axis("look_left", JOY_AXIS_RIGHT_X, -0.5)
	_add_axis("look_right", JOY_AXIS_RIGHT_X, 0.5)
	_add_axis("look_up", JOY_AXIS_RIGHT_Y, -0.5)
	_add_axis("look_down", JOY_AXIS_RIGHT_Y, 0.5)
	# Sprint (shoulder + trigger)
	_add_button("sprint", JOY_BUTTON_LEFT_SHOULDER)
	_add_axis("sprint", JOY_AXIS_TRIGGER_LEFT, 0.5)
	# Jump on Square (X)
	_remove_button("jump", JOY_BUTTON_RIGHT_SHOULDER)
	_add_button("jump", JOY_BUTTON_X)
	# Shoulder buttons for paging
	_ensure_action("ui_page_up")
	_ensure_action("ui_page_down")
	_add_button("ui_page_up", JOY_BUTTON_LEFT_SHOULDER)
	_add_button("ui_page_down", JOY_BUTTON_RIGHT_SHOULDER)
