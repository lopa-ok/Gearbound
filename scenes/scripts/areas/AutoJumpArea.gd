extends Area3D
## AutoJumpArea: when the human player enters this area, they auto-jump.
## Usage: add an Area3D to your scene, attach this script, and set properties.

@export var force_jump: bool = false # if true, jump instantly; else use buffer
@export var only_human_group: StringName = "human_player" # group gate
@export var cooldown: float = 0.2 # prevent rapid re-trigger

var _last_trigger_time: float = -1.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body or not is_instance_valid(body):
		return
	if only_human_group != StringName("") and not body.is_in_group(only_human_group):
		return
	# Debounce/cooldown
	var now := Time.get_ticks_msec() * 0.001
	if _last_trigger_time > 0.0 and (now - _last_trigger_time) < cooldown:
		return
	_last_trigger_time = now
	# Call the player's jump API if present
	if body.has_method("request_jump"):
		body.request_jump(force_jump)
