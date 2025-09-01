extends VBoxContainer

const WORLD = preload("res://scenes/RoomLevel.tscn")
const SETTINGS_MENU = preload("res://scenes/SettingsMenu.tscn")

var settings_menu: Control

func _ready():
	# Instance the settings menu and add it to the tree
	settings_menu = SETTINGS_MENU.instantiate()
	add_child(settings_menu)
	settings_menu.visible = false   # start hidden

func _on_new_game_button_pressed():
	# Play the fade-out transition
	await Transition.play_transition("transition_out")
	get_tree().change_scene_to_packed(WORLD)

func _on_quit_button_pressed():
	get_tree().quit()

func _on_settings_button_pressed():
	settings_menu.visible = true   # show settings menu on top
