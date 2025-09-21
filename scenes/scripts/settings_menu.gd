extends Control

signal closed

# Called when the scene is ready
func _ready():
	hide()  # start hidden

func grab_default_focus() -> void:
	var back := get_node_or_null("MainMenu/Back") as BaseButton
	if back:
		back.grab_focus()

func _on_back_pressed() -> void:
	hide()
	emit_signal("closed")
