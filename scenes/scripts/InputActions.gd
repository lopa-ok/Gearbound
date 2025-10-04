extends Node

func _enter_tree() -> void:
	# Ensure base movement actions (keep if already defined)
	_ensure_action_key_list("ui_left", [KEY_A, KEY_LEFT])
	_ensure_action_key_list("ui_right", [KEY_D, KEY_RIGHT])
	_ensure_action_key_list("ui_up", [KEY_W, KEY_UP])
	_ensure_action_key_list("ui_down", [KEY_S, KEY_DOWN])
	# Gameplay actions
	_ensure_action_key_list("interact", [KEY_F])
	_ensure_action_key_list("drop", [KEY_G, KEY_Q])
	_ensure_action_key_list("switch_player", [KEY_TAB])
	_ensure_action_key_list("sprint", [KEY_SHIFT])
	_ensure_action_key_list("jump", [KEY_SPACE])
	_ensure_action_key_list("crouch", [KEY_CTRL])
	# Gamepad bindings
	_ensure_action_joy_button("interact", JoyButton.JOY_BUTTON_A)
	_ensure_action_joy_button("drop", JoyButton.JOY_BUTTON_X)
	_ensure_action_joy_button("switch_player", JoyButton.JOY_BUTTON_START)
	_ensure_action_joy_button("sprint", JoyButton.JOY_BUTTON_LEFT_SHOULDER)
	_ensure_action_joy_button("jump", JoyButton.JOY_BUTTON_A)
	_ensure_action_joy_button("crouch", JoyButton.JOY_BUTTON_B)
	# Debug: list drop bindings
	var events := InputMap.action_get_events("drop")
	var keys := []
	for e in events:
		if e is InputEventKey:
			keys.append((e as InputEventKey).physical_keycode)
	print("[InputActions] drop bound keys:", keys)

func _ready() -> void:
	_ensure_interact_lmb()
	_ensure_switch_player_tab()
	_ensure_movement_actions()
	_ensure_sprint_shift()
	_ensure_gas_r2()
	_ensure_brake_l2()

func _ensure_action_key_list(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		_ensure_event(action, ev)

func _ensure_action_joy_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	_ensure_event(action, ev)

func _ensure_event(action: StringName, ev: InputEvent) -> void:
	# Avoid duplicates by comparing with existing events
	var existing := InputMap.action_get_events(action)
	for e in existing:
		if e is InputEventKey and ev is InputEventKey:
			if e.physical_keycode == (ev as InputEventKey).physical_keycode:
				return
		elif e is InputEventJoypadButton and ev is InputEventJoypadButton:
			if e.button_index == (ev as InputEventJoypadButton).button_index:
				return
	InputMap.action_add_event(action, ev)

func _ensure_movement_actions() -> void:
	_ensure_action_key("left", KEY_A)
	_ensure_action_key("left", KEY_LEFT)
	_ensure_action_key("right", KEY_D)
	_ensure_action_key("right", KEY_RIGHT)
	_ensure_action_key("forward", KEY_W)
	_ensure_action_key("forward", KEY_UP)
	_ensure_action_key("back", KEY_S)
	_ensure_action_key("back", KEY_DOWN)

func _ensure_action_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)

func _ensure_interact_lmb() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("interact", ev):
		InputMap.action_add_event("interact", ev)

func _ensure_switch_player_tab() -> void:
	if not InputMap.has_action("switch_player"):
		InputMap.add_action("switch_player")
	var ev_key := InputEventKey.new()
	ev_key.physical_keycode = KEY_TAB
	if not InputMap.action_has_event("switch_player", ev_key):
		InputMap.action_add_event("switch_player", ev_key)
	var ev_joy := InputEventJoypadButton.new()
	ev_joy.button_index = JOY_BUTTON_Y
	if not InputMap.action_has_event("switch_player", ev_joy):
		InputMap.action_add_event("switch_player", ev_joy)

func _ensure_sprint_shift() -> void:
	if not InputMap.has_action("sprint"):
		InputMap.add_action("sprint")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SHIFT
	if not InputMap.action_has_event("sprint", ev):
		InputMap.action_add_event("sprint", ev)

func _ensure_gas_r2() -> void:
	if not InputMap.has_action("gas"):
		InputMap.add_action("gas")
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_TRIGGER_RIGHT
	ev.axis_value = 1.0
	if not InputMap.action_has_event("gas", ev):
		InputMap.action_add_event("gas", ev)

func _ensure_brake_l2() -> void:
	if not InputMap.has_action("brake"):
		InputMap.add_action("brake")
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_TRIGGER_LEFT
	ev.axis_value = 1.0
	if not InputMap.action_has_event("brake", ev):
		InputMap.action_add_event("brake", ev)
