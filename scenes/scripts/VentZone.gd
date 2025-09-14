extends Node3D

@export var suppress_unstuck: bool = true
@export var area_path: NodePath
@export var auto_create_area: bool = true
@export var auto_create_shape: bool = false
@export var box_size: Vector3 = Vector3(4.0, 3.0, 4.0)
@export var area_collision_layer: int = 1
@export var area_collision_mask: int = 0x7FFFFFFF
@export var debug_log: bool = false

var _area: Area3D

func _ready() -> void:
	# Resolve or create the Area3D used to detect the player in the vent
	if area_path != NodePath(""):
		_area = get_node_or_null(area_path) as Area3D
	else:
		_area = get_node_or_null("Area3D") as Area3D
		if _area == null:
			_area = get_node_or_null("VentArea") as Area3D
	if _area == null and auto_create_area:
		_area = Area3D.new()
		_area.name = "VentArea"
		add_child(_area)
	if _area:
		_area.monitorable = true
		_area.monitoring = true
		_area.collision_layer = area_collision_layer
		_area.collision_mask = area_collision_mask
		# Optionally create a BoxShape if none is present
		if auto_create_shape and _get_collision_shape() == null:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = box_size
			cs.shape = shape
			_area.add_child(cs)
			if debug_log:
				print("[VentZone:%s] Auto-created BoxShape size=%s" % [name, str(box_size)])
		if not _area.body_entered.is_connected(_on_body_entered):
			_area.body_entered.connect(_on_body_entered)
		if not _area.body_exited.is_connected(_on_body_exited):
			_area.body_exited.connect(_on_body_exited)
		if debug_log:
			print("[VentZone:%s] Ready (area=%s)" % [name, str(_area)])

func _on_body_entered(body: Node) -> void:
	if suppress_unstuck and body and body.has_method("set_unstuck_suppressed"):
		body.set_unstuck_suppressed(true)
		if debug_log:
			print("[VentZone:%s] Suppress ON for %s" % [name, str(body)])

func _on_body_exited(body: Node) -> void:
	if suppress_unstuck and body and body.has_method("set_unstuck_suppressed"):
		body.set_unstuck_suppressed(false)
		if debug_log:
			print("[VentZone:%s] Suppress OFF for %s" % [name, str(body)])

func _get_collision_shape() -> CollisionShape3D:
	if _area == null:
		return null
	for child in _area.get_children():
		var cs := child as CollisionShape3D
		if cs:
			return cs
	return null
