extends Node3D
# Simple door that requires a key with matching item_id to unlock.
# Expected hierarchy: Node3D (this) -> Optional AnimationPlayer / Mesh / CollisionShape
# Usage: set required_key_id in Inspector. Player must carry an item_type == "key" and item_id matches.

@export var required_key_id: String = "red_key"
@export var open_on_unlock: bool = true
@export var consume_key: bool = true
@export var open_rotation_degrees: float = 90.0
@export var open_speed: float = 4.0

# Animation support
@export var use_animation: bool = true
@export var animation_player_path: NodePath
@export var open_animation: StringName = &"open"
@export var animation_speed: float = 1.0

# Proximity interaction (Area3D)
@export var use_proximity_area: bool = true
@export var use_area_path: NodePath
@export var auto_create_use_area: bool = true
@export var area_size: Vector3 = Vector3(2.5, 3.0, 2.5) # default box around door

var _is_unlocked: bool = false
var _is_open: bool = false
var _target_rot: Basis
var _closed_rot: Basis
var _anim: AnimationPlayer
var _use_area: Area3D
var _players_in_area: Array = []

func _ready():
	_closed_rot = global_transform.basis.orthonormalized()
	_target_rot = _closed_rot
	# Resolve AnimationPlayer if any
	if animation_player_path != NodePath(""):
		_anim = get_node_or_null(animation_player_path) as AnimationPlayer
	else:
		_anim = get_node_or_null("AnimationPlayer") as AnimationPlayer
	# Setup proximity area
	if use_proximity_area:
		if use_area_path != NodePath(""):
			_use_area = get_node_or_null(use_area_path) as Area3D
		else:
			_use_area = get_node_or_null("UseArea") as Area3D
		if _use_area == null and auto_create_use_area:
			_use_area = Area3D.new()
			_use_area.name = "UseArea"
			var shape := CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			(shape.shape as BoxShape3D).size = area_size
			add_child(_use_area)
			_use_area.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
			_use_area.add_child(shape)
			shape.owner = _use_area.owner
		if _use_area:
			_use_area.body_entered.connect(_on_use_area_body_entered)
			_use_area.body_exited.connect(_on_use_area_body_exited)

func _process(delta: float) -> void:
	# Skip manual rotation if using animation
	if _is_open and (not use_animation or _anim == null):
		var current: Transform3D = global_transform
		var t: float = clamp(delta * open_speed, 0.0, 1.0)
		var from_basis: Basis = current.basis.orthonormalized()
		var to_basis: Basis = _target_rot.orthonormalized()
		current.basis = from_basis.slerp(to_basis, t)
		global_transform = current

func _unhandled_input(event: InputEvent) -> void:
	if not use_proximity_area or _use_area == null:
		return
	if event.is_action_pressed("interact") and _players_in_area.size() > 0:
		# Try first valid player in area
		for p in _players_in_area:
			if is_instance_valid(p):
				if try_interact(p):
					break

func _on_use_area_body_entered(body: Node) -> void:
	# Track players inside the area (group "player" is set in player.gd)
	if body and body.is_in_group("player"):
		_players_in_area.append(body)

func _on_use_area_body_exited(body: Node) -> void:
	_players_in_area.erase(body)

func try_interact(player: Node) -> bool:
	# Fetch carried item via interface method only (avoids invalid has_variable calls)
	var item = null
	if player.has_method("get_carried_item"):
		item = player.get_carried_item()
	if item == null:
		return false
	if item.has_method("get_item_type") and item.get_item_type() == "key" and item.has_method("get_item_id") and item.get_item_id() == required_key_id:
		_unlock(player, item)
		return true
	return false

func _unlock(player: Node, key_item: Node):
	if _is_unlocked:
		return
	_is_unlocked = true
	if consume_key:
		key_item.queue_free()
		# Ask player to clear carried item if that was the key
		if player.has_method("get_carried_item") and player.get_carried_item() == key_item and player.has_method("clear_carried_item"):
			player.clear_carried_item()
	if open_on_unlock:
		_open()

func _open():
	if _is_open:
		return
	_is_open = true
	if use_animation and _anim and _anim.has_animation(open_animation):
		_anim.speed_scale = animation_speed
		_anim.play(open_animation)
		return
	# Fallback to manual slerp if no animation
	_target_rot = _closed_rot.rotated(Vector3.UP, deg_to_rad(open_rotation_degrees)).orthonormalized()
