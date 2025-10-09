# filepath: /Users/lopa/test/scenes/scripts/items/CassetteTape.gd
extends "res://scenes/scripts/PickupItem.gd"

@export var tape_stream: AudioStream
@export var tape_name: String = ""
@export var inventory_icon: Texture2D
@export var debug_log: bool = false

func _ready() -> void:
	super._ready()
	item_type = "tape"
	if tape_name == "":
		tape_name = str(name)
	if debug_log:
		var has_stream := tape_stream != null
		var has_icon := inventory_icon != null
		print("[CassetteTape:%s] Ready. item_type=%s tape_name=%s has_stream=%s icon_set=%s" % [str(name), item_type, tape_name, str(has_stream), str(has_icon)])
