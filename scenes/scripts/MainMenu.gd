extends VBoxContainer

const WORLD = preload("res://scenes/RoomLevel.tscn")
const SETTINGS_MENU = preload("res://scenes/SettingsMenu.tscn")

var settings_menu: Control
# New: defer focus until controller input is detected
var _focus_given: bool = false
var _menu_buttons: Array = []

func _ready():
	# Block pausing while main menu is active
	add_to_group("no_pause")
	set_process_input(true)
	# Ensure controller/gamepad input mappings exist
	if Engine.get_main_loop() != null:
		ControllerSupport.ensure_input_map()
	# Fade in when arriving at the main menu from another scene
	Transition.play_transition("transition_in")
	# Instance the settings menu and add it to the viewport root so it fills the screen
	settings_menu = SETTINGS_MENU.instantiate()
	# Defer add_child to avoid "parent busy" during scene setup
	get_tree().root.call_deferred("add_child", settings_menu)
	settings_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_menu.z_index = 100
	settings_menu.visible = false   # start hidden
	# Ensure menu music is playing
	var music := get_node_or_null("/root/BgMusic") as AudioStreamPlayer
	if music and music.has_method("ensure_playing"):
		music.call("ensure_playing")
	
	# Ensure any gameplay crosshair is hidden on the main menu
	var root_cross := get_node_or_null("/root/CrosshairUI") as Control
	if root_cross:
		root_cross.visible = false
	# Hide human-owned crosshair(s)
	for p in get_tree().get_nodes_in_group("human_player"):
		if p.has_method("_set_crosshair_visible"):
			p.call_deferred("_set_crosshair_visible", false)
		elif p.has_node("CrosshairLayer/Crosshair"):
			var c := p.get_node("CrosshairLayer/Crosshair") as Control
			if c:
				c.visible = false
	# Focus graph for controller navigation, but do NOT grab focus now
	var btn_new := get_node_or_null("NewGameButton") as Button
	var btn_settings := get_node_or_null("SettingsButton") as Button
	var btn_quit := get_node_or_null("QuitButton") as Button
	_menu_buttons.clear()
	if btn_new: _menu_buttons.append(btn_new)
	if btn_settings: _menu_buttons.append(btn_settings)
	if btn_quit: _menu_buttons.append(btn_quit)
	for i in _menu_buttons.size():
		var b: Button = _menu_buttons[i]
		b.focus_mode = Control.FOCUS_ALL
		var prev: Button = _menu_buttons[(i - 1 + _menu_buttons.size()) % _menu_buttons.size()]
		var next: Button = _menu_buttons[(i + 1) % _menu_buttons.size()]
		b.focus_neighbor_top = b.get_path_to(prev)
		b.focus_neighbor_bottom = b.get_path_to(next)
	# Note: intentionally do not call grab_focus() here

func _input(event: InputEvent) -> void:
	# Consume pause immediately so PauseManager won't toggle
	if event.is_action_pressed("pause"):
		accept_event()
		return

func _unhandled_input(event):
	# Give initial focus only after controller input
	if not _focus_given and _is_controller_nav(event):
		_give_initial_focus()
		# Let the same input continue to navigate; do not mark handled here
	# Block pause on main menu
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		return
	# Allow B / Cancel to close settings menu
	if event.is_action_pressed("ui_cancel") and settings_menu and settings_menu.visible:
		settings_menu.visible = false
		get_viewport().set_input_as_handled()
		return
	# A / Accept should trigger the focused button
	if event.is_action_pressed("ui_accept"):
		var f := get_viewport().gui_get_focus_owner()
		if f and f is Button:
			(f as Button).emit_signal("pressed")
			get_viewport().set_input_as_handled()
			return

func _is_controller_nav(event: InputEvent) -> bool:
	var jb := event as InputEventJoypadButton
	if jb and jb.pressed:
		return true
	var jm := event as InputEventJoypadMotion
	if jm:
		if (jm.axis == JOY_AXIS_LEFT_X or jm.axis == JOY_AXIS_LEFT_Y) and absf(jm.axis_value) > 0.2:
			return true
	return false

func _give_initial_focus() -> void:
	if _menu_buttons.size() > 0:
		var first: Button = _menu_buttons[0]
		first.grab_focus()
		_focus_given = true

func _on_new_game_button_pressed():
	# Cache the SceneTree before awaiting, as this node may be temporarily removed from the tree
	var tree: SceneTree = get_tree()
	await Transition.play_transition("transition_out")
	if tree:
		tree.change_scene_to_packed(WORLD)

func _on_quit_button_pressed():
	get_tree().quit()

func _on_settings_button_pressed():
	# Ensure the node is in the tree before showing
	if settings_menu and not settings_menu.is_inside_tree():
		await get_tree().process_frame
	# Ensure BG music continues in menus
	var music := get_node_or_null("/root/BgMusic") as AudioStreamPlayer
	if music and music.has_method("ensure_playing"):
		music.call("ensure_playing")
	settings_menu.visible = true   # show settings menu on top
