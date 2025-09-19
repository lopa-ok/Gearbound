extends Node

@export var start_active: StringName = &"human" # or &"rc"
var active: StringName

signal active_changed(which: StringName)

func _ready() -> void:
	active = start_active
	emit_signal("active_changed", active)

func set_active(which: StringName) -> void:
	if active == which:
		return
	active = which
	emit_signal("active_changed", active)

func is_human_active() -> bool:
	return active == &"human"

func is_rc_active() -> bool:
	return active == &"rc"