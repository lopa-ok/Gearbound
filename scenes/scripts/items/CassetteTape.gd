# filepath: /Users/lopa/test/scenes/scripts/items/CassetteTape.gd
extends "res://scenes/scripts/PickupItem.gd"

@export var tape_stream: AudioStream
@export var tape_name: String = ""
@export var inventory_icon: Texture2D
@export var debug_log: bool = false
@export var tape_id: String = ""
@export var default_stream: AudioStream
@export var phase_streams: Dictionary = {} # { phase_name: AudioStream, "default": AudioStream }

func _ready() -> void:
	super._ready()
	item_type = "tape"
	if tape_name == "":
		tape_name = str(name)
	if debug_log:
		var has_stream := tape_stream != null
		var has_icon := inventory_icon != null
		print("[CassetteTape:%s] Ready. item_type=%s tape_name=%s has_stream=%s icon_set=%s" % [str(name), item_type, tape_name, str(has_stream), str(has_icon)])

func get_current_stream() -> AudioStream:
	var r := TapeRouter.get_or_create()
	if r:
		var s := r.get_stream_for(self)
		if s:
			return s
	# Fallbacks
	if default_stream:
		return default_stream
	if "tape_stream" in self and self.tape_stream != null:
		return self.tape_stream
	if "stream" in self and self.stream != null:
		return self.stream
	return null

func get_tape_stream() -> AudioStream:
	return get_current_stream()
