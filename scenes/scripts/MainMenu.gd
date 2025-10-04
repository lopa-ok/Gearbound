extends VBoxContainer

const WORLD = preload("res://scenes/RoomLevel.tscn")
const SETTINGS_MENU = preload("res://scenes/SettingsMenu.tscn")

var settings_menu: Control

func _ready():
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

func _on_new_game_button_pressed():
	# Play the fade-out transition
	await Transition.play_transition("transition_out")
	get_tree().change_scene_to_packed(WORLD)

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
