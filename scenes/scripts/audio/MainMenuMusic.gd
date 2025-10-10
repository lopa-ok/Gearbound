extends Node

@export var main_stream: AudioStream
@export var fade_in: float = 1.0
@export var fade_out: float = 1.0
@export var priority: int = 100
@export var debug_log: bool = false
@export var block_pause: bool = true
@export var blocked_actions: PackedStringArray = ["pause", "ui_cancel"]
@export var loop_main: bool = true
@export var menu_volume_db: float = -12.0

var _id: String = ""

func _ready() -> void:
	_id = "main_menu_" + str(get_path())
	set_process_input(true)
	var mm := MusicManager.get_or_create()
	if mm and main_stream:
		if debug_log:
			print("[MainMenuMusic] requesting main track")
		mm.request_area_music(_id, main_stream, fade_in, priority, loop_main, menu_volume_db)
	elif debug_log:
		print("[MainMenuMusic] no stream assigned; nothing to play")

func _exit_tree() -> void:
	var mm := MusicManager.get_or_create()
	if mm:
		if debug_log:
			print("[MainMenuMusic] releasing main track")
		mm.release_area_music(_id, fade_out)

func _input(event: InputEvent) -> void:
	if not block_pause:
		return
	if event is InputEventAction and event.pressed:
		var act := (event as InputEventAction).action
		if blocked_actions.has(act):
			accept_event()  # consume so PauseMenu/UI won’t see it
