extends Node

var _menu: Control
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _settings: Control = null

func _ready():
	# Receive input while paused so ESC can unpause
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Preload and instance the pause menu UI
	var scene := load("res://scenes/PauseMenu.tscn") as PackedScene
	if scene:
		_menu = scene.instantiate() as Control
		if _menu:
			_menu.process_mode = Node.PROCESS_MODE_ALWAYS
			# Use deferred add to avoid "Parent node is busy setting up children" errors
			get_tree().root.call_deferred("add_child", _menu)
			_menu.visible = false
			# Connect button callbacks if script exposes them
			if _menu.has_method("connect_signals"):
				_menu.call("connect_signals", Callable(self, "_on_resume"), Callable(self, "_on_restart"), Callable(self, "_on_settings"), Callable(self, "_on_quit"))

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()

func toggle_pause() -> void:
	if get_tree().paused:
		_resume()
	else:
		_pause()

func _ensure_menu_in_tree():
	if _menu and _menu.get_parent() == null:
		get_tree().root.call_deferred("add_child", _menu)

func _pause() -> void:
	_prev_mouse_mode = Input.mouse_mode
	get_tree().paused = true
	_ensure_menu_in_tree()
	if _menu:
		# Defer show & focus so the Control is inside the tree before grabbing focus
		_menu.call_deferred("show")
		if _menu.has_method("grab_default_focus"):
			_menu.call_deferred("grab_default_focus")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_crosshair_visible(false)

func _resume() -> void:
	# Close settings if open
	_close_settings_if_any()
	if _menu:
		_menu.visible = false
	get_tree().paused = false
	# Restore previous mouse mode
	Input.mouse_mode = _prev_mouse_mode
	_set_crosshair_visible(true)

# Button handlers (connected by menu)
func _on_resume() -> void:
	_resume()

func _on_restart() -> void:
	var cs := get_tree().current_scene
	if cs:
		var path := cs.scene_file_path
		_resume()
		if path != "":
			get_tree().change_scene_to_file(path)

func _on_settings() -> void:
	# Instance SettingsMenu if present
	var ps := load("res://scenes/SettingsMenu.tscn") as PackedScene
	if ps:
		var inst := ps.instantiate()
		if inst:
			_settings = inst as Control
			_settings.process_mode = Node.PROCESS_MODE_ALWAYS
			# Hide pause menu while settings is open
			if _menu:
				_menu.visible = false
			# Re-show the pause menu when settings closes, if it emits a signal
			if _settings.has_signal("closed"):
				_settings.connect("closed", Callable(self, "_on_settings_closed"))
			# Use deferred add and show to avoid setup timing issues
			get_tree().root.call_deferred("add_child", _settings)
			_settings.call_deferred("show")
			if _settings.has_method("grab_default_focus"):
				_settings.call_deferred("grab_default_focus")

func _on_settings_closed() -> void:
	# Free settings and bring back the pause menu
	if _settings and is_instance_valid(_settings):
		_settings.queue_free()
		_settings = null
	if _menu and get_tree().paused:
		_menu.show()
		if _menu.has_method("grab_default_focus"):
			_menu.grab_default_focus()

func _close_settings_if_any() -> void:
	if _settings and is_instance_valid(_settings):
		_settings.queue_free()
		_settings = null

func _on_quit() -> void:
	_resume()
	get_tree().quit()

func _set_crosshair_visible(vis: bool) -> void:
	# Prefer telling the HumanPlayer to toggle its own crosshair UI
	var did := false
	for p in get_tree().get_nodes_in_group("human_player"):
		if p and p.has_method("_set_crosshair_visible"):
			p.call("_set_crosshair_visible", vis)
			did = true
	# Fallback: try to locate a Crosshair Control under players
	if not did:
		for p in get_tree().get_nodes_in_group("human_player"):
			var cross := p.get_node_or_null("CrosshairLayer/Crosshair")
			if cross and cross is CanvasItem:
				(cross as CanvasItem).visible = vis
				did = true
				break
	# Final fallback: legacy root-level node search (kept for compatibility)
	if not did:
		var root := get_tree().root
		var cross2 := root.get_node_or_null("CrosshairUI")
		if cross2:
			if cross2.has_method("_set_crosshair_visible"):
				cross2._set_crosshair_visible(vis)
			elif cross2.has_method("set_visible"):
				cross2.set_visible(vis)
			elif cross2 is CanvasItem:
				cross2.visible = vis
	return
