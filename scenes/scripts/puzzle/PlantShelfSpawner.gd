extends Node3D

signal spawn_complete(count: int)

@export var plant_variants: Array[PackedScene] = [
	preload("res://resources/FurnitureScenes/Plant.tscn"),
	preload("res://resources/FurnitureScenes/BigPlant.tscn"),
]
@export_range(0, 64) var min_count := 1
@export_range(0, 64) var max_count := 6
@export var randomize_rotation_y := true
@export var randomize_scale := true
@export var scale_range := Vector2(0.9, 1.2)
@export var y_offset := 0.0
@export var spawn_under_parent := false # if true, spawned plants will be parented to this node's parent
@export var item_group_name := "shelf_item" # group assigned to spawned items for easy counting
# New: drive spawn count from keypad code
@export var use_keypad_code := false
@export var keypad_path: NodePath
@export_range(0, 9) var code_digit_index := 0
@export var respawn_on_keypad_success := true

var _spawned_nodes: Array[Node] = []

func _ready() -> void:
	add_to_group("plant_shelf_spawner")
	randomize()
	# Optionally connect to keypad to respawn when code succeeds or changes
	if use_keypad_code:
		var kp := get_node_or_null(keypad_path)
		if kp:
			# Only hook success if requested
			if respawn_on_keypad_success and kp.has_signal("code_success") and not kp.is_connected("code_success", Callable(self, "respawn")):
				kp.connect("code_success", Callable(self, "respawn"))
			 # Always react to code changes so spawn count follows keypad code
			if kp.has_signal("code_changed") and not kp.is_connected("code_changed", Callable(self, "_on_keypad_code_changed")):
				kp.connect("code_changed", Callable(self, "_on_keypad_code_changed"))
	_do_spawn()

# Handle keypad code_changed(new_code: String) by respawning
func _on_keypad_code_changed(_new_code: String) -> void:
	respawn()

func respawn() -> void:
	_clear_spawned()
	_do_spawn()

func _do_spawn() -> void:
	if plant_variants.is_empty():
		push_warning("PlantShelfSpawner: No plant_variants set; nothing to spawn.")
		await get_tree().process_frame
		emit_signal("spawn_complete", 0)
		return
	var points := _get_spawn_points()
	if points.is_empty():
		push_warning("PlantShelfSpawner: No spawn points found. Add Marker3D children under 'SpawnPoints' (or directly under this node).")
		await get_tree().process_frame
		emit_signal("spawn_complete", 0)
		return
	var count := _determine_spawn_count(points.size())
	points.shuffle()
	for i in count:
		var plant_scene: PackedScene = plant_variants.pick_random()
		if plant_scene == null:
			continue
		var plant := plant_scene.instantiate()
		if plant == null:
			continue
		var parent_node = get_parent() if spawn_under_parent else self
		parent_node.add_child(plant)
		if plant is Node3D:
			var target_xform: Transform3D = points[i].global_transform
			target_xform.origin.y += y_offset
			(plant as Node3D).global_transform = target_xform
			if randomize_rotation_y:
				(plant as Node3D).rotate_y(randf() * TAU)
			if randomize_scale:
				var s := randf_range(scale_range.x, scale_range.y)
				(plant as Node3D).scale *= Vector3.ONE * s
		# Tag for counting by other systems
		plant.add_to_group(item_group_name)
		_spawned_nodes.append(plant)
	# Inform listeners that spawn is done (next frame so listeners in _ready can connect first)
	await get_tree().process_frame
	emit_signal("spawn_complete", count)

# Helper: check if an Object exposes a given property
func _has_property(obj: Object, prop_name: StringName) -> bool:
	var plist := obj.get_property_list()
	for p in plist:
		if p.get("name") == prop_name:
			return true
	return false

func _determine_spawn_count(max_points: int) -> int:
	if use_keypad_code:
		var kp := get_node_or_null(keypad_path)
		if kp:
			var code_str := ""
			if kp.has_method("get_correct_code"):
				code_str = str(kp.call("get_correct_code"))
			elif _has_property(kp, "correct_code"):
				code_str = str(kp.get("correct_code"))
			if code_str.length() > code_digit_index:
				var ch := code_str.substr(code_digit_index, 1)
				if ch.is_valid_int():
					var d := int(ch)
					# Enforce 1..6 and available points
					return clamp(d, 1, min(6, max_points))
	# Fallback to random 1..6 when not using keypad code
	var c := randi_range(1, 6)
	return clamp(c, 1, min(6, max_points))

func _clear_spawned() -> void:
	for n in _spawned_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_spawned_nodes.clear()

func _get_spawn_points() -> Array:
	var container: Node = self
	if has_node("SpawnPoints"):
		container = get_node("SpawnPoints")
	var pts: Array = []
	for c in container.get_children():
		if c is Marker3D or c is Node3D:
			pts.append(c)
	return pts
