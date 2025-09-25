extends Node3D

# External locks
@export var lock_paths: Array[NodePath] = []
@export var locks_required: int = 3
@export var auto_open_on_final_unlock: bool = true

# Manual open fallback (match KeyDoor)
@export var open_rotation_degrees: float = 90.0
@export var open_speed: float = 4.0

# Animation support (same style as KeyDoor.gd)
@export var use_animation: bool = true
@export var animation_player_path: NodePath
@export var open_animation: StringName = &"open"
@export var animation_speed: float = 1.0

# Proximity interaction (Area3D)
@export var use_proximity_area: bool = true
@export var use_area_path: NodePath
@export var auto_create_use_area: bool = true
@export var area_size: Vector3 = Vector3(2.5, 3.0, 2.5)

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
# New: debounce interact to avoid double-toggle
@export var interact_cooldown: float = 0.25

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
# New: next time an interact is allowed
var _next_interact_ok_time: float = 0.0

# Locks bookkeeping
var _locks: Array[Node] = []
var _locks_unlocked: int = 0

func _ready():
	_closed_rot = global_transform.basis.orthonormalized()
	_target_rot = _closed_rot
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
	# Collect locks and connect to their "unlocked" signal if present
	_locks.clear()
	for lp in lock_paths:
		var l := get_node_or_null(lp)
		if l:
			_locks.append(l)
			if l.has_signal("unlocked"):
				l.connect("unlocked", Callable(self, "_on_lock_signal"))
		else:
			push_warning("[MultiLockDoor] Lock node not found at path: %s" % [lp])
	_refresh_locks()
	_is_unlocked = _locks_unlocked >= locks_required and locks_required > 0
	if debug_log:
		print("[MultiLockDoor:%s] Ready | locks=%d req=%d unlocked=%d" % [name, _locks.size(), locks_required, _locks_unlocked])

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
	# Ignore key-repeat echoes
	if event is InputEventAction and event.is_echo():
		return
	if event.is_action_pressed("interact") and _players_in_area.size() > 0:
		if debug_log: print("[MultiLockDoor:%s] Proximity interact attempt. Players in area=%d" % [name, _players_in_area.size()])
		for p in _players_in_area:
			if is_instance_valid(p):
				if try_interact(p):
					if debug_log: print("[MultiLockDoor:%s] Interact succeeded via proximity list" % name)
					break

func _on_use_area_body_entered(body: Node) -> void:
	if body and body.is_in_group("player"):
		_players_in_area.append(body)
		if debug_log: print("[MultiLockDoor:%s] Player entered area: %s" % [name, body.name])

func _on_use_area_body_exited(body: Node) -> void:
	_players_in_area.erase(body)
	if debug_log and body: print("[MultiLockDoor:%s] Player exited area: %s" % [name, body.name])

func try_interact(player: Node) -> bool:
	if debug_log:
		print("[MultiLockDoor:%s] try_interact by %s" % [name, player.name])
	# Debounce: avoid double-toggle in same/adjacent frame(s)
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now < _next_interact_ok_time:
		if debug_log: print("[MultiLockDoor:%s] Skipping interact (cooldown)" % name)
		return false
	# Only human players can operate the door
	if not _is_human_player(player):
		if debug_log:
			print("[MultiLockDoor:%s] Blocked: non-human interactor" % name)
		return false
	# Optional interact press gating (if present)
	if require_interact_press and not Input.is_action_pressed("interact"):
		if debug_log: print("[MultiLockDoor:%s] FAIL: interact press required but not held" % name)
		return false
	# Require crosshair aim for human if enabled
	var cross_ok := (not require_human_crosshair) or _is_crosshair_on_self(player)
	if debug_log:
		print("[MultiLockDoor:%s] Crosshair gate => require=%s ok=%s" % [name, str(require_human_crosshair), str(cross_ok)])
	if require_human_crosshair and not cross_ok:
		if debug_log: print("[MultiLockDoor:%s] FAIL: crosshair not on door" % name)
		return false
	# Toggle close when already open
	if _is_open and allow_human_close:
		if debug_log: print("[MultiLockDoor:%s] Closing door" % name)
		_start_close_helper()
		_next_interact_ok_time = now + interact_cooldown
		return true
	# Try to unlock child locks when aiming at the door
	_forward_interact_to_locks(player)
	# Refresh/compute locks
	_refresh_locks()
	if debug_log:
		print("[MultiLockDoor:%s] Locks status: %d/%d" % [name, _locks_unlocked, locks_required])
		for l in _locks:
			var rid: String = ""
			var flag: bool = false
			if l:
				var v1 = l.get("required_key_id")
				if typeof(v1) == TYPE_STRING:
					rid = v1
				var v2 = l.get("is_unlocked")
				if typeof(v2) == TYPE_BOOL:
					flag = v2
			var lname: String
			if l:
				lname = l.name
			else:
				lname = "?"
			print("  - lock=%s required_key_id=%s is_unlocked=%s" % [lname, rid, str(flag)])
	var enough := (locks_required <= 0) or (_locks_unlocked >= locks_required)
	if _is_unlocked or enough:
		_is_unlocked = true
		if not _is_open:
			if debug_log: print("[MultiLockDoor:%s] Unlocked (%d/%d), opening" % [name, _locks_unlocked, locks_required])
			_start_open_helper()
			_next_interact_ok_time = now + interact_cooldown
			return true
	# Not enough locks
	if debug_log:
		_play_locked_sfx()
		print("[MultiLockDoor:%s] FAIL: locked (%d/%d)" % [name, _locks_unlocked, locks_required])
	return false

func _is_human_player(node: Node) -> bool:
	return node is CharacterBody3D

# Fallback player camera resolver (robust)
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
	if debug_log and cam:
		print("[MultiLockDoor:%s] Camera candidate: %s current=%s" % [name, cam.name, str(cam.current)])
	if cam == null:
		if debug_log: print("[MultiLockDoor:%s] Crosshair check: no camera found on player" % name)
		return false
	if not cam.current and debug_log:
		print("[MultiLockDoor:%s] Camera not current; proceeding anyway" % name)
	var vp := cam.get_viewport()
	if vp == null:
		if debug_log: print("[MultiLockDoor:%s] Crosshair check: no viewport" % name)
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
		if debug_log: print("[MultiLockDoor:%s] Crosshair ray miss" % name)
		return false
	var collider: Node = res.get("collider") as Node
	if collider == null:
		return false
	var n := collider
	var hit_self := self == n or self.is_ancestor_of(n)
	if debug_log:
		print("[MultiLockDoor:%s] Crosshair hit=%s (ancestor=%s) distance=%.2f" % [name, n.name, str(hit_self), origin.distance_to(res.get("position", origin))])
	return hit_self

func _get_anim_player() -> AnimationPlayer:
	var ap: AnimationPlayer = null
	if animation_player_path != NodePath(""):
		ap = get_node_or_null(animation_player_path) as AnimationPlayer
	if ap == null:
		ap = get_node_or_null("AnimationPlayer") as AnimationPlayer
	return ap

func _get_open_anim_name() -> StringName:
	return open_animation if use_animation else &"open"

func _get_anim_speed() -> float:
	return float(animation_speed)

func _ensure_anim_connected(ap: AnimationPlayer) -> void:
	if ap and not ap.animation_finished.is_connected(_on_keydoor_anim_finished):
		ap.animation_finished.connect(_on_keydoor_anim_finished)

func _find_first_mesh() -> MeshInstance3D:
	for c in get_children():
		var m := c as MeshInstance3D
		if m:
			return m
	return null

func _find_first_collision() -> CollisionObject3D:
	var co: CollisionObject3D = get_node_or_null("StaticBody3D") as CollisionObject3D
	if co:
		return co
	for c in get_children():
		var cc := c as CollisionObject3D
		if cc:
			return cc
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
	# Mark as unlocked on first close, so future opens require no locks check (already satisfied previously)
	_is_unlocked = true
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
	_is_open = true
	_play_open_sfx()
	# Fallback manual rotation target if no animation
	if not _anim:
		_target_rot = _closed_rot.rotated(Vector3.UP, deg_to_rad(open_rotation_degrees)).orthonormalized()

func _finalize_close_helper() -> void:
	var co := _find_first_collision()
	if co:
		co.set_deferred("disabled", false)
	_is_open = false

func _on_keydoor_anim_finished(anim_name: StringName) -> void:
	if anim_name != _get_open_anim_name():
		return
	if _helper_anim_active == 1:
		_finalize_open_helper()
	elif _helper_anim_active == -1:
		_finalize_close_helper()
	_helper_anim_active = 0

func _play_open_sfx():
	if _open_sfx:
		_open_sfx.play()

func _play_locked_sfx():
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now >= _locked_sfx_next_time:
		_locked_sfx_next_time = now + sfx_locked_cooldown
		if _locked_sfx:
			_locked_sfx.play()

# Locks helpers
func _on_lock_signal(_a = null) -> void:
	_refresh_locks()
	if debug_log:
		print("[MultiLockDoor:%s] Lock update: %d/%d" % [name, _locks_unlocked, locks_required])
	# Auto-open when the last required lock is unlocked
	if auto_open_on_final_unlock and not _is_open and locks_required > 0 and _locks_unlocked >= locks_required:
		_is_unlocked = true
		if debug_log:
			print("[MultiLockDoor:%s] Auto-open triggered (%d/%d)" % [name, _locks_unlocked, locks_required])
		_start_open_helper()

func _refresh_locks() -> void:
	var cnt := 0
	for l in _locks:
		if _lock_is_unlocked(l):
			cnt += 1
	_locks_unlocked = cnt

func _lock_is_unlocked(l: Node) -> bool:
	if l == null:
		return false
	var v = l.get("is_unlocked")
	if typeof(v) == TYPE_BOOL:
		return v
	if l.has_method("is_unlocked"):
		var r = l.call("is_unlocked")
		return typeof(r) == TYPE_BOOL and r
	var v2 = l.get("unlocked")
	if typeof(v2) == TYPE_BOOL:
		return v2
	return false

# New: forward interaction to locks when aiming at the door
func _forward_interact_to_locks(player: Node) -> void:
	# If player is aiming at the door, try to unlock locks by forwarding the interaction
	# This bypasses each lock's own crosshair requirement, but still respects require_interact_press
	if require_human_crosshair and not _is_crosshair_on_self(player):
		return
	for l in _locks:
		if l and l.has_method("try_interact_from_door"):
			l.call("try_interact_from_door", player)

# Debug utility to print full door/locks state
func debug_dump() -> void:
	print("[MultiLockDoor:%s] Dump => is_open=%s is_unlocked=%s req=%d unlocked=%d" % [name, str(_is_open), str(_is_unlocked), locks_required, _locks_unlocked])
	var i := 0
	for l in _locks:
		var rid: String = ""
		var flag: bool = false
		if l:
			var v1 = l.get("required_key_id")
			if typeof(v1) == TYPE_STRING:
				rid = v1
			var v2 = l.get("is_unlocked")
			if typeof(v2) == TYPE_BOOL:
				flag = v2
		var lname: String
		if l:
			lname = l.name
		else:
			lname = "?"
		print("  [%d] lock=%s required_key_id=%s is_unlocked=%s" % [i, lname, rid, str(flag)])
		i += 1
