extends Control

func connect_signals(resume_cb: Callable, restart_cb: Callable, settings_cb: Callable, quit_cb: Callable, hints_cb: Callable = Callable()) -> void:
	$Panel/VBox/Resume.pressed.connect(resume_cb)
	$Panel/VBox/Restart.pressed.connect(restart_cb)
	$Panel/VBox/Settings.pressed.connect(settings_cb)
	$Panel/VBox/Quit.pressed.connect(quit_cb)
	if has_node("Panel/VBox/Hints"):
		if hints_cb.is_valid():
			$Panel/VBox/Hints.pressed.connect(hints_cb)
		elif has_node("HintsMenu"):
			$Panel/VBox/Hints.pressed.connect(Callable(self, "_on_hints_pressed"))
			# Ensure the HintsMenu Back button closes it
			var hm := $HintsMenu
			if hm and hm.has_method("connect_signals"):
				hm.connect_signals(Callable(self, "_on_hints_back"))

func grab_default_focus() -> void:
	$Panel/VBox/Resume.grab_focus()

func _on_hints_pressed() -> void:
	if has_node("HintsMenu"):
		$HintsMenu.open()

func _on_hints_back() -> void:
	if has_node("HintsMenu"):
		$HintsMenu.close()
