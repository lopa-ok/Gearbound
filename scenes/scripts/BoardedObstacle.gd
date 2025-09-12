extends Node3D
# Obstacle removable with a crowbar tool (item_type == "crowbar").
# Optionally consumes the crowbar.

@export var consume_crowbar: bool = false
@export var break_time: float = 0.5

var _is_removed := false
var _timer := 0.0
var _breaking := false

func _process(delta):
	if _breaking:
		_timer += delta
		if _timer >= break_time:
			_remove()

func try_interact(player: Node) -> bool:
	if _is_removed:
		return false
	var item = null
	if player.has_method("get_carried_item"):
		item = player.get_carried_item()
	if item and item.has_method("get_item_type") and item.get_item_type() == "crowbar":
		_start_break(player, item)
		return true
	return false

func _start_break(player: Node, crowbar_item: Node):
	if _breaking: return
	_breaking = true
	_timer = 0.0
	if consume_crowbar:
		crowbar_item.queue_free()
		if player.has_method("get_carried_item") and player.get_carried_item() == crowbar_item and player.has_method("clear_carried_item"):
			player.clear_carried_item()

func _remove():
	_is_removed = true
	_breaking = false
	visible = false
	set_process(false)
	# Optionally queue_free() if you prefer removal
	# queue_free()
