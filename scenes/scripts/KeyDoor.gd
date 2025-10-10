extends Node3D
# Simple door that requires a key with matching item_id to unlock.
# Expected hierarchy: Node3D (this) -> Optional AnimationPlayer / Mesh / CollisionShape
# Usage: set required_key_id in Inspector. Player must carry an item_type == "key" and item_id matches.

@export var required_key_id: String = "red_key"
# When false, the door behaves as already unlocked and does not require a key
@export var require_key: bool = true
@export var open_on_unlock: bool = true
@export var consume_key: bool = true
@export var open_rotation_degrees: float = 90.0
@export var open_speed: float = 4.0
# New: spawn opened at start (instant) or play the open animation at start
@export var start_open: bool = false
@export var start_open_play_anim: bool = false

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

# SFX support
@export var open_sfx_path: NodePath
@export var locked_sfx_path: NodePath
@export var sfx_locked_cooldown: float = 0.35

# Require human to aim crosshair on this to interact; RC car can still use proximity
@export var require_human_crosshair: bool = true
@export var aim_max_distance: float = 6.0

@export var debug_log: bool = true

@export var allow_human_close: bool = true

@export var require_interact_press: bool = false

# Optional lock mesh that will be hidden once unlocked/opened
@export var lock_mesh_path: NodePath
@export var auto_hide_lock_on_unlock: bool = true

var _is_unlocked: bool = false
var _is_open: bool = false
var _target_rot: Basis
var _closed_rot: Basis
var _anim: AnimationPlayer
var _use_area: Area3D
var _players_in_area: Array = []
var _open_sfx: AudioStreamPlayer3D
var _locked_sfx: AudioStreamPlayer3D
var _locked_sfx_next_time: float = 0.0
var _helper_anim_active: int = 0 # 1=open via helper, -1=close via helper, 0=idle
var _lock_mesh: Node3D

func _ready():
	_closed_rot = global_transform.basis.orthonormalized()
	_target_rot = _closed_rot
	# If key is not required, treat as unlocked from the start
	if not require_key:
		_is_unlocked = true
	# Resolve AnimationPlayer if any
	if animation_player_path != NodePath(""):
		_anim = get_node_or_null(animation_player_path) as AnimationPlayer
	else:
		_anim = get_node_or_null("AnimationPlayer") as AnimationPlayer
	# Resolve SFX players (optional)
	if open_sfx_path != NodePath(""):
		_open_sfx = get_node_or_null(open_sfx_path) as AudioStreamPlayer3D
	else:
		_open_sfx = get_node_or_null("OpenSFX") as AudioStreamPlayer3D
	if locked_sfx_path != NodePath(""):
		_locked_sfx = get_node_or_null(locked_sfx_path) as AudioStreamPlayer3D
	else:
		_locked_sfx = get_node_or_null("LockedSFX") as AudioStreamPlayer3D
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
	# Resolve optional lock mesh
	_resolve_lock_mesh()
	# If already unlocked (e.g., require_key=false), hide lock
	if _is_unlocked and auto_hide_lock_on_unlock:
		_hide_lock_mesh()
	# NEW: optionally start opened
	if start_open:
		_is_unlocked = true
		_hide_lock_mesh()
		var ap := _get_anim_player()
		var anim := _get_open_anim_name()
		if use_animation and ap and ap.has_animation(anim):
			if start_open_play_anim:
				_helper_anim_active = 1
				_ensure_anim_connected(ap)
				ap.play(anim, -1.0, _get_anim_speed(), false)
			else:
				ap.play(anim)
				var a := ap.get_animation(anim)
				var len := a.length if a else 0.0
				ap.seek(len, true)
				ap.stop()
		else:
			# Snap rotation instantly to the open angle
			var t := global_transform
			t.basis = _closed_rot.rotated(Vector3.UP, deg_to_rad(open_rotation_degrees)).orthonormalized()
			global_transform = t
		_finalize_open_helper()

func _resolve_lock_mesh() -> void:
	_lock_mesh = null
	if lock_mesh_path != NodePath(""):
		_lock_mesh = get_node_or_null(lock_mesh_path) as Node3D
	if _lock_mesh == null:
		_lock_mesh = get_node_or_null("LockMesh") as Node3D
	if _lock_mesh == null:
		var door := get_node_or_null("doorway(Clone)/door")
		if door:
			_lock_mesh = door.get_node_or_null("LockMesh") as Node3D
	if debug_log:
		print("[KeyDoor:%s] Lock mesh resolved: %s" % [name, str(_lock_mesh)])

func _hide_lock_mesh() -> void:
	if not auto_hide_lock_on_unlock:
		return
	if _lock_mesh:
		_lock_mesh.visible = false

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
		if debug_log: print("[KeyDoor:%s] Proximity interact attempt. Players in area=%d" % [name, _players_in_area.size()])
		for p in _players_in_area:
			if is_instance_valid(p):
				if try_interact(p):
					if debug_log: print("[KeyDoor:%s] Interact succeeded via proximity list" % name)
					break

func _on_use_area_body_entered(body: Node) -> void:
	# Track players inside the area (group "player" is set in player.gd)
	if body and body.is_in_group("player"):
		_players_in_area.append(body)
		if debug_log: print("[KeyDoor:%s] Player entered area: %s" % [name, body.name])

func _on_use_area_body_exited(body: Node) -> void:
	_players_in_area.erase(body)
	if debug_log and body: print("[KeyDoor:%s] Player exited area: %s" % [name, body.name])

func _consume_key_if_needed(player: Node) -> void:
	var do_consume := ("consume_key" in self) and bool(consume_key)
	if not do_consume:
		return
	if player and player.has_method("get_carried_item"):
		var it: Node = player.get_carried_item()
		if it:
			it.queue_free()
			if player.has_method("clear_carried_item"):
				player.clear_carried_item()

func try_interact(player: Node) -> bool:
	if debug_log: print("[KeyDoor:%s] try_interact called by %s" % [name, player.name])
	# Only human players can operate the door
	if not _is_human_player(player):
		if debug_log:
			print("[KeyDoor:%s] Blocked: non-human interactor" % name)
		return false
	# Optional interact press gating (if present)
	if ("require_interact_press" in self) and require_interact_press and not Input.is_action_pressed("interact"):
		if debug_log: print("[KeyDoor:%s] FAIL: interact press required but not held" % name)
		return false
	# Require crosshair aim for human if enabled
	if require_human_crosshair and not _is_crosshair_on_self(player):
		if debug_log: print("[KeyDoor:%s] FAIL: crosshair not on door" % name)
		return false
	# If the door does not require a key, ensure it's marked unlocked and proceed
	if not require_key:
		_is_unlocked = true
	# Toggle close when already open
	if _is_open and allow_human_close:
		if debug_log: print("[KeyDoor:%s] Closing door" % name)
		_start_close_helper()
		return true
	# If unlocked already, just hide lock (if any) and open without a key
	if _is_unlocked and not _is_open:
		if debug_log: print("[KeyDoor:%s] Already unlocked, opening" % name)
		_hide_lock_mesh()
		_start_open_helper()
		return true
	# If player has correct key, mark unlocked, consume if needed, hide lock, and open
	if _player_has_required_key(player):
		_is_unlocked = true
		if debug_log: print("[KeyDoor:%s] Key matched. Unlocking & opening. consume_key=%s" % [name, str(consume_key)])
		_consume_key_if_needed(player)
		_hide_lock_mesh()
		_start_open_helper()
		return true
	if debug_log:
		_play_locked_sfx()
		print("[KeyDoor:%s] FAIL: player lacks key (required=%s)" % [name, str(required_key_id)])
	return false

func _is_human_player(node: Node) -> bool:
	return node is CharacterBody3D

# Fallback player camera resolver (robust)
func _get_player_camera(player: Node) -> Camera3D:
	# Direct common fields
	if "camera_3d" in player and player.camera_3d is Camera3D:
		return player.camera_3d
	if "_cam" in player and player._cam is Camera3D:
		return player._cam
	# Named child lookup
	var direct := player.get_node_or_null("Camera3D")
	if direct is Camera3D:
		return direct
	# Pivot path (common pattern: Pivot/Camera3D or CameraPivot/Camera3D)
	var pivots = ["Pivot", "CameraPivot"]
	for p in pivots:
		var pivot = player.get_node_or_null(p)
		if pivot:
			var cam = pivot.get_node_or_null("Camera3D")
			if cam is Camera3D:
				return cam
	# Breadth-first search (last resort)
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
	if debug_log and cam:
		print("[KeyDoor:%s] Camera candidate: %s current=%s" % [name, cam.name, str(cam.current)])
	if cam == null:
		if debug_log: print("[KeyDoor:%s] Crosshair check: no camera found on player" % name)
		return false
	# Allow using the camera even if not flagged current (e.g., switched late) but warn.
	if not cam.current and debug_log:
		print("[KeyDoor:%s] Camera not current; proceeding anyway" % name)
	var vp := cam.get_viewport()
	if vp == null:
		if debug_log: print("[KeyDoor:%s] Crosshair check: no viewport" % name)
		return false
	var center: Vector2 = vp.get_visible_rect().size * 0.5
	var origin: Vector3 = cam.project_ray_origin(center)
	var dir: Vector3 = cam.project_ray_normal(center)
	var to: Vector3 = origin + dir * (aim_max_distance if "aim_max_distance" in self else 8.0)
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, to)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.exclude = [player]
	var res := space.intersect_ray(params)
	if res.is_empty():
		if debug_log: print("[KeyDoor:%s] Crosshair ray miss" % name)
		return false
	var collider: Node = res.get("collider") as Node
	if collider == null:
		return false
	var n := collider
	var hit_self := self == n or self.is_ancestor_of(n)
	if debug_log:
		print("[KeyDoor:%s] Crosshair hit=%s (ancestor=%s) distance=%.2f" % [name, n.name, str(hit_self), origin.distance_to(res.get("position", origin))])
	return hit_self

func _unlock(player: Node, key_item: Node):
	if _is_unlocked:
		return
	_is_unlocked = true
	if consume_key:
		key_item.queue_free()
		# Ask player to clear carried item if that was the key
		if player.has_method("get_carried_item") and player.get_carried_item() == key_item and player.has_method("clear_carried_item"):
			player.clear_carried_item()
	_hide_lock_mesh()
	if open_on_unlock:
		_open()

func _open():
	if _is_open:
		return
	_is_open = true
	_play_open_sfx()
	_hide_lock_mesh()
	if use_animation and _anim and _anim.has_animation(open_animation):
		_anim.speed_scale = animation_speed
		_anim.play(open_animation)
		return
	# Fallback to manual slerp if no animation
	_target_rot = _closed_rot.rotated(Vector3.UP, deg_to_rad(open_rotation_degrees)).orthonormalized()

func _play_open_sfx():
	if _open_sfx:
		_open_sfx.play()

func _play_locked_sfx():
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now >= _locked_sfx_next_time:
		_locked_sfx_next_time = now + sfx_locked_cooldown
		if _locked_sfx:
			_locked_sfx.play()

func _get_anim_player() -> AnimationPlayer:
	var ap: AnimationPlayer = null
	if "animation_player_path" in self and animation_player_path != NodePath(""):
		ap = get_node_or_null(animation_player_path) as AnimationPlayer
	if ap == null:
		ap = get_node_or_null("AnimationPlayer") as AnimationPlayer
	return ap

func _get_open_anim_name() -> StringName:
	if "open_animation" in self:
		return open_animation
	return &"open"

func _get_anim_speed() -> float:
	if "animation_speed" in self:
		return float(animation_speed)
	return 1.0

func _ensure_anim_connected(ap: AnimationPlayer) -> void:
	if ap and not ap.animation_finished.is_connected(_on_keydoor_anim_finished):
		ap.animation_finished.connect(_on_keydoor_anim_finished)

func _find_first_mesh() -> MeshInstance3D:
	# Try direct children first
	for c in get_children():
		var m := c as MeshInstance3D
		if m:
			return m
	# Fallback: breadth-first search among descendants
	var q: Array = []
	for c in get_children(): q.append(c)
	while q.size() > 0:
		var n = q.pop_front()
		if n is MeshInstance3D:
			return n
		for c2 in n.get_children(): q.append(c2)
	return null

func _find_first_collision() -> CollisionObject3D:
	# Try a common direct child first
	var co: CollisionObject3D = get_node_or_null("StaticBody3D") as CollisionObject3D
	if co:
		return co
	# Check direct children
	for c in get_children():
		var cc := c as CollisionObject3D
		if cc:
			return cc
	# Fallback: breadth-first search among descendants
	var q: Array = []
	for c in get_children(): q.append(c)
	while q.size() > 0:
		var n = q.pop_front()
		if n is CollisionObject3D:
			return n
		for c2 in n.get_children(): q.append(c2)
	return null

func _start_open_helper() -> void:
	var ap := _get_anim_player()
	var anim := _get_open_anim_name()
	if ap and ap.has_animation(anim):
		_helper_anim_active = 1
		_ensure_anim_connected(ap)
		var sp: float = _get_anim_speed()
		ap.play(anim, -1.0, sp, false)
	else:
		_finalize_open_helper()

func _start_close_helper() -> void:
	# Mark as unlocked on first close, so future opens require no key
	_is_unlocked = true
	# Ensure mesh is visible during the closing animation
	var m := _find_first_mesh()
	if m:
		m.visible = true
	var ap := _get_anim_player()
	var anim := _get_open_anim_name()
	if ap and ap.has_animation(anim):
		_helper_anim_active = -1
		_ensure_anim_connected(ap)
		var sp: float = _get_anim_speed()
		ap.play(anim, -1.0, -absf(sp), true)
	else:
		_finalize_close_helper()

func _finalize_open_helper() -> void:
	var co := _find_first_collision()
	if co:
		co.set_deferred("disabled", true)
	# Keep mesh visible so the open animation leaves the door visible
	_is_open = true
	_hide_lock_mesh()

func _finalize_close_helper() -> void:
	var co := _find_first_collision()
	if co:
		co.set_deferred("disabled", false)
	# Mesh should already be visible from _start_close_helper, but ensure it stays visible
	var m := _find_first_mesh()
	if m:
		m.visible = true
	_is_open = false
	_helper_anim_active = 0

func _on_keydoor_anim_finished(anim_name: StringName) -> void:
	if anim_name != _get_open_anim_name():
		return
	if _helper_anim_active == 1:
		_finalize_open_helper()
		_helper_anim_active = 0
	elif _helper_anim_active == -1:
		_finalize_close_helper()
		_helper_anim_active = 0

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
		if debug_log: print("[KeyDoor:%s] Key check: no carried item (all fallbacks)" % name)
		return false
	var id: String = ""
	if item.has_method("get_item_id"):
		id = str(item.get_item_id())
	elif "item_id" in item:
		id = str(item.item_id)
	var required := str(required_key_id) if "required_key_id" in self else "(unset)"
	var ok := id == required
	if debug_log: print("[KeyDoor:%s] Key check: carried=%s required=%s match=%s (item=%s)" % [name, id, required, str(ok), item.name])
	return ok
