extends Node

func _ready() -> void:
	_ensure_interact_lmb()
	_ensure_switch_player_tab()

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
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_TAB
	if not InputMap.action_has_event("switch_player", ev):
		InputMap.action_add_event("switch_player", ev)