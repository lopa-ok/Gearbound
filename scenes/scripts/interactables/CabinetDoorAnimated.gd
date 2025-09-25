extends Node3D

@export var anim_player_path: NodePath = NodePath("AnimationPlayer")
@export var open_anim: StringName = &"open"
@export var close_anim: StringName = &"close"

var _ap: AnimationPlayer
var _is_open: bool = false
var _busy: bool = false

func _ready() -> void:
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if _ap:
		set_process(false)
		set_physics_process(false)
		_ap.animation_finished.connect(_on_anim_finished)

func try_interact(_user: Node) -> bool:
	if _busy or _ap == null:
		return false
	_busy = true
	if _is_open:
		if _ap.has_animation(close_anim):
			_ap.play(close_anim)
		elif _ap.has_animation(open_anim):
			# Fallback: play open() backwards if close() doesn’t exist
			_ap.play_backwards(open_anim)
		else:
			_busy = false
			return false
	else:
		if _ap.has_animation(open_anim):
			_ap.play(open_anim)
		elif _ap.has_animation(close_anim):
			_ap.play_backwards(close_anim)
		else:
			_busy = false
			return false
	return true

func get_interact_label() -> String:
	if _is_open:
		return "Close"
	return "Open"

func _on_anim_finished(_anim: StringName) -> void:
	_is_open = not _is_open
	_busy = false
