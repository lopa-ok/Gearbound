extends VBoxContainer

const WORLD = preload("res://scenes/RoomLevel.tscn")
const SETTINGS_MENU = preload("res://scenes/SettingsMenu.tscn")

var settings_menu: Control

func _ready():
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
	# Focus and wire focus neighbors for controller navigation
	var btn_new := get_node_or_null("NewGameButton") as Button
	var btn_settings := get_node_or_null("SettingsButton") as Button
	var btn_quit := get_node_or_null("QuitButton") as Button
	var buttons: Array = []
	if btn_new: buttons.append(btn_new)
	if btn_settings: buttons.append(btn_settings)
	if btn_quit: buttons.append(btn_quit)
	for i in buttons.size():
		var b: Button = buttons[i]
		b.focus_mode = Control.FOCUS_ALL
		var prev: Button = buttons[(i - 1 + buttons.size()) % buttons.size()]
		var next: Button = buttons[(i + 1) % buttons.size()]
		b.focus_neighbor_top = b.get_path_to(prev)
		b.focus_neighbor_bottom = b.get_path_to(next)
	if btn_new:
		# Defer focus to ensure nothing steals it this frame
		btn_new.call_deferred("grab_focus")

func _unhandled_input(event):
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
