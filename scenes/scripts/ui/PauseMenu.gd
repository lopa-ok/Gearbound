extends Control

func connect_signals(resume_cb: Callable, restart_cb: Callable, settings_cb: Callable, quit_cb: Callable) -> void:
	$Panel/VBox/Resume.pressed.connect(resume_cb)
	$Panel/VBox/Restart.pressed.connect(restart_cb)
	$Panel/VBox/Settings.pressed.connect(settings_cb)
	$Panel/VBox/Quit.pressed.connect(quit_cb)

func grab_default_focus() -> void:
	$Panel/VBox/Resume.grab_focus()
