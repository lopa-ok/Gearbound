extends Node3D

@export var spawn_group: StringName = &"item_spawn"      # Group containing spawn points (Node3D/Marker3D)
@export var item_scenes: Array[PackedScene] = []           # Pool of random non-key items
@export_range(0.0, 1.0, 0.01) var per_point_chance: float = 0.7
@export var max_spawns: int = -1                           # -1 = unlimited

# Crowbar-only mode: if set, we will spawn exactly one crowbar at a random point
@export var crowbar_scene: PackedScene

# Guarantees: spawn one key item per id using this scene
@export var ensure_key_scene: PackedScene
@export var ensure_key_ids: PackedStringArray = []         # e.g. ["red_key", "vent_key"]

# RNG control (-1 randomize each run; set to a value for reproducible layouts)
@export var rng_seed: int = -1

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	# Defer spawning to avoid add_child during parent setup
	call_deferred("_do_spawn")

func _do_spawn() -> void:
	var points := _collect_points()
	if points.is_empty():
		return
	points.shuffle()
	# --- Crowbar-only path: spawn exactly one crowbar, then exit ---
	if crowbar_scene != null:
		var inst := _spawn_at(points[0], crowbar_scene)
		# Ensure this crowbar will work on the vent by giving it id=vent_key and type=crowbar
		_tag_item_id(inst, "vent_key")
		_tag_item_type(inst, "crowbar")
		if inst is Node3D:
			var n3d := inst as Node3D
			inst.tree_entered.connect(func(): n3d.scale = Vector3(0.2, 0.2, 0.2))
		return
	var used := 0
	# Ensure required keys first (if configured)
	if ensure_key_scene and ensure_key_ids.size() > 0:
		var needed: int = min(ensure_key_ids.size(), points.size())
		for i in range(needed):
			var inst := _spawn_at(points[i], ensure_key_scene)
			_tag_item_id(inst, ensure_key_ids[i])
			used += 1
	# Randomly fill remaining points from pool
	var spawned := 0
	for i in range(used, points.size()):
		if max_spawns >= 0 and spawned >= max_spawns:
			break
		if rng.randf() > per_point_chance:
			continue
		if item_scenes.is_empty():
			break
		var scene := item_scenes[rng.randi_range(0, item_scenes.size() - 1)]
		_spawn_at(points[i], scene)
		spawned += 1

func _collect_points() -> Array[Node3D]:
	var pts: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(spawn_group):
		if n is Node3D:
			pts.append(n)
	return pts

func _spawn_at(p: Node3D, scene: PackedScene) -> Node:
	if p == null or scene == null:
		return null
	var inst := scene.instantiate()
	# Set transform after it enters the tree to preserve world position
	if inst is Node3D:
		var target_xf := p.global_transform
		inst.tree_entered.connect(func(): (inst as Node3D).global_transform = target_xf)
	var parent := get_tree().current_scene if get_tree().current_scene else get_tree().root
	parent.call_deferred("add_child", inst)
	return inst

func _tag_item_id(inst: Node, id_str: String) -> void:
	if inst == null:
		return
	# Prefer methods if available
	if inst.has_method("set_item_id"):
		inst.set_item_id(str(id_str))
		return
	# Fallback to property if defined by script (e.g., PickupItem.gd exports item_id)
	if "item_id" in inst:
		inst.item_id = str(id_str)

func _tag_item_type(inst: Node, type_str: String) -> void:
	if inst == null:
		return
	# Prefer methods if available
	if inst.has_method("set_item_type"):
		inst.set_item_type(str(type_str))
		return
	# Fallback to property if defined by script (e.g., PickupItem.gd exports item_type)
	if "item_type" in inst:
		inst.item_type = str(type_str)
