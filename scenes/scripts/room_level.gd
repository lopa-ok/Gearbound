extends Node

func _ready():
	# When the level loads, fade in
	Transition.play_transition("transition_in")
