extends Node3D

@export var hint_title: String = "Hint"
@export_multiline var hint_text: String = "Write your hint here."
@export var use_rich_text: bool = true
@export var pause_on_open: bool = true
@export var close_on_interact_again: bool = true
@export var debug_log: bool = false

var _dialog: AcceptDialog
var _label: Control
var _opened_by_pause: bool = false

func try_interact(_user: Node) -> bool:
	if _dialog and _dialog.visible:
		if close_on_interact_again:
			_dialog.hide()
			return true
		return false
	_show_hint_popup()
	return true

func _show_hint_popup() -> void:
	if debug_log:
		print("[HintItem:%s] show popup" % name)
	if _dialog == null:
		_create_dialog()
	if pause_on_open and not get_tree().paused:
		_opened_by_pause = true
		get_tree().paused = true
	_dialog.show()
	_dialog.popup_centered_ratio(0.35)

func _create_dialog() -> void:
	_dialog = AcceptDialog.new()
	_dialog.title = hint_title
	_dialog.exclusive = true
	_dialog.min_size = Vector2(560, 280)
	_dialog.always_on_top = true
	_dialog.unresizable = false
	# Ensure it still processes input while paused (2 == PAUSE_MODE_PROCESS)
	_dialog.pause_mode = 2
	# Content
	if use_rich_text:
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.text = hint_text
		_label = r
		_dialog.add_child(r)
	else:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = hint_text
		_label = l
		_dialog.add_child(l)
	# Buttons & signals
	_dialog.get_ok_button().text = "OK"
	_dialog.confirmed.connect(_on_dialog_closed)
	_dialog.close_requested.connect(_on_dialog_closed)
	# Add to UI
	get_tree().root.add_child(_dialog)
	_dialog.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null

func set_hint(text: String, title: String = "") -> void:
	if title != "":
		hint_title = title
	if is_instance_valid(_dialog):
		_dialog.title = hint_title
	# Update content
	hint_text = text
	if is_instance_valid(_label):
		if _label is RichTextLabel:
			(_label as RichTextLabel).text = hint_text
		elif _label is Label:
			(_label as Label).text = hint_text

func _on_dialog_closed() -> void:
	if debug_log:
		print("[HintItem:%s] popup closed" % name)
	if _opened_by_pause and get_tree().paused:
		get_tree().paused = false
	_opened_by_pause = false

# Optional helper to open from other scripts
func open_now() -> void:
	_show_hint_popup()
