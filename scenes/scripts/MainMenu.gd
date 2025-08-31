extends VBoxContainer

const WORLD = preload("res://scenes/RoomLevel.tscn")

func _on_new_game_button_pressed():
	# Play the fade-out transition
	await Transition.play_transition("transition_out")
	get_tree().change_scene_to_packed(WORLD)

func _on_quit_button_pressed():
	get_tree().quit()
