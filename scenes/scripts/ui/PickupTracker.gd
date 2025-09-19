extends Node

var _shown_types: Dictionary = {}

func has_shown(type_id: String) -> bool:
	return _shown_types.has(type_id)

func mark_shown(type_id: String) -> void:
	_shown_types[type_id] = true
