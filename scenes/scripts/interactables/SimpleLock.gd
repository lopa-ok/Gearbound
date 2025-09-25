extends Node3D

signal unlocked(lock: Node)

@export var required_key_id: String = "red_key"
@export var consume_key: bool = true
@export var debug_log: bool = true

# Proximity interaction (Area3D)
@export var use_proximity_area: bool = true
@export var use_area_path: NodePath
@export var auto_create_use_area: bool = true
@export var area_size: Vector3 = Vector3(1.0, 1.0, 1.0)

# Aim gating like KeyDoor
@export var require_human_crosshair: bool = true
@export var aim_max_distance: float = 6.0
@export var require_interact_press: bool = false

@export var animation_player_path: NodePath
@export var play_animation_on_unlock: bool = true
@export var unlock_animation: StringName = &"unlock"
@export var animation_speed: float = 1.0
@export var hide_after_animation: bool = false

var is_unlocked: bool = false

var _use_area: Area3D
var _players_in_area: Array = []
var _anim: AnimationPlayer = null
var _anim_connected: bool = false

func _ready():
	# Setup proximity area (optional)
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
	_resolve_anim()

func _unhandled_input(event: InputEvent) -> void:
	if not use_proximity_area or _use_area == null:
		return
	if event.is_action_pressed("interact") and _players_in_area.size() > 0:
		for p in _players_in_area:
			if is_instance_valid(p):
				if try_interact(p):
					break

func _on_use_area_body_entered(body: Node) -> void:
	if body and body.is_in_group("player"):
		_players_in_area.append(body)
		if debug_log: print("[SimpleLock:%s] Player entered area: %s" % [name, body.name])

func _on_use_area_body_exited(body: Node) -> void:
	_players_in_area.erase(body)
	if debug_log and body: print("[SimpleLock:%s] Player exited area: %s" % [name, body.name])

# Public: regular interact (requires crosshair if enabled)
func try_interact(player: Node) -> bool:
	return _try_interact(player, false)

# Public: forwarded interact from a parent door; bypass crosshair gating
func try_interact_from_door(player: Node) -> bool:
	return _try_interact(player, true)

# Internal interaction handler
func _try_interact(player: Node, bypass_crosshair: bool) -> bool:
	if debug_log:
		print("[SimpleLock:%s] try_interact by %s | unlocked=%s require_press=%s require_crosshair=%s bypass_crosshair=%s" % [name, player.name, str(is_unlocked), str(require_interact_press), str(require_human_crosshair), str(bypass_crosshair)])
	if is_unlocked:
		if debug_log: print("[SimpleLock:%s] Already unlocked" % name)
		return false
	# Optional interact press gating
	if require_interact_press and not Input.is_action_pressed("interact"):
		if debug_log: print("[SimpleLock:%s] Interact press required but not held" % name)
		return false
	# Require crosshair aim for human if enabled (unless bypassed)
	if require_human_crosshair and not bypass_crosshair and not _is_crosshair_on_self(player):
		if debug_log: print("[SimpleLock:%s] Crosshair not on lock" % name)
		return false
	# Check key
	if _player_has_required_key(player):
		if debug_log: print("[SimpleLock:%s] Correct key. Unlocking" % name)
		_consume_key_if_needed(player)
		_set_unlocked()
		return true
	if debug_log: print("[SimpleLock:%s] FAIL: player lacks key (required=%s)" % [name, str(required_key_id)])
	return false

func _set_unlocked() -> void:
	is_unlocked = true
	if debug_log:
		print("[SimpleLock:%s] >>> UNLOCKED! Emitting signal." % name)
	emit_signal("unlocked", self)
	if play_animation_on_unlock:
		_play_unlock_animation()
	else:
		# No animation: hide immediately
		visible = false

func _consume_key_if_needed(player: Node) -> void:
	if not consume_key:
		return
	if player and player.has_method("get_carried_item"):
		var it: Node = player.get_carried_item()
		if it:
			if debug_log: print("[SimpleLock:%s] Consuming carried item: %s" % [name, it.name])
			it.queue_free()
			if player.has_method("clear_carried_item"):
				player.clear_carried_item()

# Key check copied to match KeyDoor.gd behavior
func _player_has_required_key(player: Node) -> bool:
	# First try standard accessor
	var item: Node = null
	if player.has_method("get_carried_item"):
		item = player.get_carried_item()
	# Fallback: look for likely carried child nodes (common names)
	if item == null:
		var carry_names = ["CarryPoint", "carry_point", "Carried", "Hand"]
		for n in carry_names:
			var cp = player.get_node_or_null(n)
			if cp:
				for c in cp.get_children():
					if c is Node3D:
						item = c
						break
			if item:
				break
	if item == null:
		if debug_log: print("[SimpleLock:%s] Key check: no carried item" % name)
		return false
	var id: String = ""
	if item.has_method("get_item_id"):
		id = str(item.get_item_id())
	elif "item_id" in item:
		id = str(item.item_id)
	var required := str(required_key_id)
	var ok := id == required
	if debug_log:
		print("[SimpleLock:%s] Key check: carried=%s required=%s match=%s (item=%s path=%s)" % [name, id, required, str(ok), item.name, item.get_path()])
	return ok

# Crosshair aim helpers (mirrors KeyDoor.gd)
func _get_player_camera(player: Node) -> Camera3D:
	if "camera_3d" in player and player.camera_3d is Camera3D:
		return player.camera_3d
	if "_cam" in player and player._cam is Camera3D:
		return player._cam
	var direct := player.get_node_or_null("Camera3D")
	if direct is Camera3D:
		return direct
	var pivots = ["Pivot", "CameraPivot"]
	for p in pivots:
		var pivot = player.get_node_or_null(p)
		if pivot:
			var cam = pivot.get_node_or_null("Camera3D")
			if cam is Camera3D:
				return cam
	var q: Array = []
	for c in player.get_children(): q.append(c)
	while q.size() > 0:
		var n = q.pop_front()
		if n is Camera3D:
			return n
		for c2 in n.get_children(): q.append(c2)
	return null

func _is_crosshair_on_self(player: Node) -> bool:
	var cam := _get_player_camera(player)
	if cam == null:
		if debug_log: print("[SimpleLock:%s] Crosshair check: no camera" % name)
		return false
	var vp := cam.get_viewport()
	if vp == null:
		if debug_log: print("[SimpleLock:%s] Crosshair check: no viewport" % name)
		return false
	var center: Vector2 = vp.get_visible_rect().size * 0.5
	var origin: Vector3 = cam.project_ray_origin(center)
	var dir: Vector3 = cam.project_ray_normal(center)
	var to: Vector3 = origin + dir * aim_max_distance
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, to)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.exclude = [player]
	var res := space.intersect_ray(params)
	if res.is_empty():
		if debug_log: print("[SimpleLock:%s] Crosshair ray miss" % name)
		return false
	var collider: Node = res.get("collider") as Node
	if collider == null:
		return false
	var n := collider
	var hit_self := self == n or self.is_ancestor_of(n)
	if debug_log:
		var pos: Vector3 = origin
		if res.has("position"):
			pos = res["position"]
		print("[SimpleLock:%s] Crosshair hit=%s ancestor=%s dist=%.2f" % [name, n.name, str(hit_self), origin.distance_to(pos)])
	return hit_self

func _resolve_anim():
	if animation_player_path != NodePath(""):
		_anim = get_node_or_null(animation_player_path) as AnimationPlayer
	if _anim == null:
		_anim = get_node_or_null("AnimationPlayer") as AnimationPlayer

func _play_unlock_animation():
	_resolve_anim()
	if _anim and _anim.has_animation(unlock_animation):
		if not _anim_connected:
			_anim.animation_finished.connect(_on_unlock_anim_finished)
			_anim_connected = true
		_anim.play(unlock_animation, -1.0, animation_speed, false)
	else:
		# No animation: hide immediately
		visible = false

func _on_unlock_anim_finished(anim_name: StringName):
	if anim_name != unlock_animation:
		return
	# Always hide after the unlock animation for now
	visible = false

# Extra helper to quickly dump state while testing
func debug_dump(player: Node = null) -> void:
	print("[SimpleLock:%s] Dump => unlocked=%s required_key_id=%s in_area=%d" % [name, str(is_unlocked), required_key_id, _players_in_area.size()])
	if player:
		var has := _player_has_required_key(player)
		print("[SimpleLock:%s] Player %s has_key=%s" % [name, player.name, str(has)])
