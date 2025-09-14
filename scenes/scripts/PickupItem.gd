extends Node3D
# Generic pickup item with proximity label & pickup callbacks.
# Add this root node automatically to group used by player detection.

@export var pickup_prompt: String = ""
@export var carry_offset: Vector3 = Vector3.ZERO  # local offset while on car roof (added after parenting)
@export var disable_process_on_pick: bool = true
# NEW: item metadata
@export var item_type: String = "key"   # e.g. key, crowbar
@export var item_id: String = "red_key"            # specific identifier (e.g. red_key)
# Label facing
@export var label_face_player: bool = true
@export var label_face_yaw_only: bool = true
@export var label_face_flip: bool = true

var _carried: bool = false
var _car_ref: Node = null
var _original_parent: Node = null
var _area: Area3D
var _label: Label3D
var _static_body: CollisionObject3D
var _player_near: bool = false

func _ready():
	add_to_group("pickup_item")
	_original_parent = get_parent()
	_area = get_node_or_null("Area3D")
	_label = get_node_or_null("Label3D")
	if _label:
		_label.visible = false
		# Preserve any symbol/text set in the scene; only set if empty
		if str(_label.text) == "":
			_label.text = pickup_prompt
	_static_body = get_node_or_null("StaticBody3D") as CollisionObject3D
	if _area:
		_area.body_entered.connect(_on_body_entered)
		_area.body_exited.connect(_on_body_exited)
	# Ensure we can rotate label toward camera
	if label_face_player:
		set_process(true)

func _process(_delta: float) -> void:
	if not label_face_player or _label == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if label_face_yaw_only:
		var to_cam := cam.global_transform.origin - _label.global_transform.origin
		to_cam.y = 0.0
		if to_cam.length() > 0.001:
			_label.look_at(_label.global_transform.origin + to_cam, Vector3.UP)
			if label_face_flip:
				_label.rotate_y(PI)
	else:
		_label.look_at(cam.global_transform.origin, Vector3.UP)
		if label_face_flip:
			_label.rotate_y(PI)

func is_carried() -> bool:
	return _carried

func can_be_picked() -> bool:
	return not _carried and _player_near

func on_picked_up(car: Node, carry_point: Node):
	_carried = true
	_car_ref = car
	_player_near = false
	if _label: _label.visible = false
	if _area: _area.monitoring = false
	# Keep world transform, then parent to carry point and zero local.
	var wt = global_transform
	reparent(carry_point)
	global_transform = wt # maintain orientation
	# Snap to carry point + offset
	transform.origin = carry_offset
	# Disable collisions / processing if desired
	if _static_body:
		_static_body.set_deferred("disabled", true)
	if disable_process_on_pick:
		set_process(false)
		set_physics_process(false)

func on_dropped(_car: Node):
	if not _carried:
		return
	_carried = false
	var wt = global_transform
	# Reparent back to original parent (scene root or container)
	if _original_parent:
		reparent(_original_parent)
	global_transform = wt
	if _static_body:
		_static_body.set_deferred("disabled", false)
	if disable_process_on_pick:
		set_process(true)
		set_physics_process(true)
	if _area:
		_area.monitoring = true
	_car_ref = null

func _on_body_entered(body: Node):
	if _carried:
		return
	if body.is_in_group("player"):
		_player_near = true
		if _label: _label.visible = true

func _on_body_exited(body: Node):
	if _carried:
		return
	if body.is_in_group("player"):
		_player_near = false
		if _label: _label.visible = false

func get_item_type() -> String:
	return item_type

func get_item_id() -> String:
	return item_id
