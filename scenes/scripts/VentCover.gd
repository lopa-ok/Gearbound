extends Node3D
# Vent cover unlockable with a specific key (matches item_id like KeyDoor).
# Player aims at it and presses "interact" while carrying the key.
# Optional pry_time can delay opening; key is consumed after successful open if consume_key is true.

@export var required_key_id: String = "vent_key"
@export var consume_key: bool = false
@export var pry_time: float = 0.0

# Animation (optional)
@export var use_animation: bool = false
@export var animation_player_path: NodePath
@export var open_animation: StringName = &"open"
@export var animation_speed: float = 1.0
# Pivot support
@export var pivot_path: NodePath
@export var auto_create_pivot: bool = true
@export var animated_node_path: NodePath
@export var preserve_scale_during_anim: bool = true

# SFX (optional)
@export var pry_sfx_path: NodePath
@export var open_sfx_path: NodePath

# Proximity interaction (Area3D)
@export var use_proximity_area: bool = true
@export var use_area_path: NodePath
@export var auto_create_use_area: bool = true
@export var area_size: Vector3 = Vector3(5.0, 4.0, 5.0)
@export var area_collision_mask: int = 0x7FFFFFFF # detect all by default
@export var debug_log: bool = true
@export var accepted_item_types: PackedStringArray = ["key", "crowbar"]
@export var ignore_item_type: bool = false
@export var require_interact_press: bool = true
# Require human to aim crosshair on this to interact; RC car can still use proximity
@export var require_human_crosshair: bool = true
@export var aim_max_distance: float = 6.0

# Behavior
@export var queue_free_on_open: bool = false

var _is_open := false
var _is_prying := false
var _timer := 0.0
var _anim: AnimationPlayer
var _pry_sfx: AudioStreamPlayer3D
var _open_sfx: AudioStreamPlayer3D
var _pending_consume_item: Node = null
var _use_area: Area3D
var _players_in_area: Array = []
var _input_edge: bool = false
var _pivot: Node3D
var _anim_node: Node3D
var _anim_orig_scale: Vector3 = Vector3.ONE
# Track left mouse for just-pressed detection in physics
var _lmb_down_prev: bool = false

func _ready():
	if animation_player_path != NodePath(""):
		_anim = get_node_or_null(animation_player_path) as AnimationPlayer
	else:
		_anim = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if pry_sfx_path != NodePath(""):
		_pry_sfx = get_node_or_null(pry_sfx_path) as AudioStreamPlayer3D
	else:
		_pry_sfx = get_node_or_null("PrySFX") as AudioStreamPlayer3D
	if open_sfx_path != NodePath(""):
		_open_sfx = get_node_or_null(open_sfx_path) as AudioStreamPlayer3D
	else:
		_open_sfx = get_node_or_null("OpenSFX") as AudioStreamPlayer3D
	# Proximity Area
	if use_proximity_area:
		if use_area_path != NodePath(""):
			_use_area = get_node_or_null(use_area_path) as Area3D
		else:
			_use_area = get_node_or_null("UseArea") as Area3D
		if not _use_area and auto_create_use_area:
			_use_area = Area3D.new()
			_use_area.name = "UseArea"
			add_child(_use_area)
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = area_size
			cs.shape = shape
			_use_area.add_child(cs)
			_use_area.monitorable = true
			_use_area.monitoring = true
			if debug_log:
				_dbg("Auto-created UseArea")
		if _use_area:
			_use_area.collision_mask = area_collision_mask
			if debug_log:
				_dbg("UseArea ready size=%s mask=%s" % [str(area_size), str(area_collision_mask)])
		if _use_area and not _use_area.body_entered.is_connected(_on_use_area_body_entered):
			_use_area.body_entered.connect(_on_use_area_body_entered)
		if _use_area and not _use_area.body_exited.is_connected(_on_use_area_body_exited):
			_use_area.body_exited.connect(_on_use_area_body_exited)
		# Ensure any pre-existing BoxShape3D matches the new size
		_ensure_area_shape_size()
	# Ensure we only process while prying
	set_process(false)
	set_physics_process(true)
	set_process_unhandled_input(true)
	# Resolve/auto-create pivot and reparent mesh/collision under it
	_ensure_pivot()
	# Resolve the node that gets animated (defaults to pivot)
	if animated_node_path != NodePath(""):
		_anim_node = get_node_or_null(animated_node_path) as Node3D
	else:
		_anim_node = _pivot
	if _anim_node:
		_anim_orig_scale = _anim_node.scale
	# Connect animation finished to finalize open
	if use_animation and _anim and not _anim.animation_finished.is_connected(_on_anim_finished):
		_anim.animation_finished.connect(_on_anim_finished)
	if debug_log:
		_dbg("Ready: use_proximity_area=%s, required_key_id=%s" % [str(use_proximity_area), required_key_id])

func _process(delta: float) -> void:
	if _is_prying:
		_timer += delta
		if _timer >= pry_time:
				_open()
	# Preserve animated node scale while animation plays (helps with scaled scenes)
	if preserve_scale_during_anim and use_animation and _anim and _anim.is_playing() and _anim_node:
		if _anim_node.scale != _anim_orig_scale:
			_anim_node.scale = _anim_orig_scale

func _physics_process(_delta: float) -> void:
	# Poll input to avoid reliance on unhandled_input ordering
	if _is_open or not use_proximity_area:
		return
	if _players_in_area.is_empty():
		return
	# Detect left mouse just-pressed
	var lmb_now: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var lmb_just: bool = lmb_now and not _lmb_down_prev
	_lmb_down_prev = lmb_now
	if Input.is_action_just_pressed("interact") or lmb_just:
		_input_edge = true
		if debug_log:
			_dbg("Interact pressed (physics): players_in_area=%d" % _players_in_area.size())
		for p in _players_in_area:
			if is_instance_valid(p) and try_interact(p):
				break
		_input_edge = false

func _unhandled_input(event: InputEvent) -> void:
	if _is_open or not use_proximity_area:
		return
	if not _players_in_area:
		return
	var lmb_evt: bool = false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		lmb_evt = mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.is_echo()
	if event.is_action_pressed("interact") or lmb_evt:
		_input_edge = true
		if debug_log:
			_dbg("Interact pressed (unhandled_input): players_in_area=%d" % _players_in_area.size())
		# Try interact for the first valid player in area
		for p in _players_in_area:
			if is_instance_valid(p):
				if try_interact(p):
					break
		_input_edge = false

func try_interact(player: Node) -> bool:
	# Try to unlock/open using a carried item whose item_id matches required_key_id.
	if _is_open:
		return false
	if require_interact_press and not (_input_edge or Input.is_action_pressed("interact")):
		if debug_log:
			_dbg("Blocked: interact not pressed")
		return false
	var item: Node = null
	if player and player.has_method("get_carried_item"):
		item = player.get_carried_item()
	if item == null:
		if debug_log:
			_dbg("No carried item")
		return false
	var item_type := _get_item_type(item)
	var item_id := _get_item_id(item)
	if debug_log:
		_dbg("Carried item type=%s id=%s (need id=%s, types=%s)" % [item_type, item_id, required_key_id, ",".join(accepted_item_types)])
	var type_ok := ignore_item_type or _is_item_type_accepted(item_type)
	if type_ok and item_id == required_key_id:
		# If human, require that the crosshair aims at this; car stays proximity-based
		if require_human_crosshair and _is_human_player(player) and not _is_crosshair_on_self(player):
			if debug_log:
				_dbg("Blocked: human not aiming at vent")
			return false
		_start_unlock(player, item)
		return true
	if debug_log:
		_dbg("Item mismatch: type_ok=%s id_ok=%s" % [str(type_ok), str(item_id == required_key_id)])
	return false

func _is_item_type_accepted(t: String) -> bool:
	return accepted_item_types.has(t)

func _start_unlock(_player: Node, key_item: Node):
	if _is_prying or _is_open:
		return
	if debug_log:
		_dbg("Start unlock: pry_time=%.2f, consume_key=%s" % [pry_time, str(consume_key)])
	_pending_consume_item = key_item if consume_key else null
	if pry_time > 0.0:
		_is_prying = true
		_timer = 0.0
		set_process(true)
		if _pry_sfx:
			_pry_sfx.play()
			if debug_log:
				_dbg("Pry SFX played")
	else:
		_open()

func _open():
	_is_open = true
	_is_prying = false
	# Stop processing once opened
	set_process(false)
	if debug_log:
		_dbg("Opened. Using animation=%s" % str(use_animation and _anim and _anim.has_animation(open_animation)))
	if _open_sfx:
		_open_sfx.play()
		if debug_log:
			_dbg("Open SFX played")
	if use_animation and _anim and _anim.has_animation(open_animation):
		_anim.speed_scale = animation_speed
		_anim.play(open_animation)
		return
	# Fallback: no animation, finalize immediately
	_finalize_open()

func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == open_animation:
		if preserve_scale_during_anim and _anim_node:
			_anim_node.scale = _anim_orig_scale
		_finalize_open()

func _finalize_open() -> void:
	# Hide mesh and disable collisions once open
	var mesh: MeshInstance3D = null
	if _pivot:
		for c in _pivot.get_children():
			mesh = c as MeshInstance3D
			if mesh:
				break
	if mesh == null:
		mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh:
		mesh.visible = false
	var sb := get_node_or_null("StaticBody3D") as CollisionObject3D
	if sb:
		sb.set_deferred("disabled", true)
	# Consume key after a successful open
	if _pending_consume_item:
		var player := _find_player_holding(_pending_consume_item)
		_pending_consume_item.queue_free()
		if player and player.has_method("clear_carried_item"):
			player.clear_carried_item()
		_pending_consume_item = null
		if debug_log:
			_dbg("Consumed key item")
	if queue_free_on_open:
		queue_free()

func _on_use_area_body_entered(body: Node) -> void:
	if _is_valid_player(body):
		_players_in_area.append(body)
		if body.has_method("set_unstuck_suppressed"):
			body.set_unstuck_suppressed(true)
		if debug_log:
			_dbg("Body entered: %s, now %d inside" % [str(body), _players_in_area.size()])

func _on_use_area_body_exited(body: Node) -> void:
	if body in _players_in_area:
		_players_in_area.erase(body)
		if body.has_method("set_unstuck_suppressed"):
			body.set_unstuck_suppressed(false)
		if debug_log:
			_dbg("Body exited: %s, now %d inside" % [str(body), _players_in_area.size()])

func _is_valid_player(node: Node) -> bool:
	return node and (node.is_in_group("player") or node.has_method("get_carried_item"))

func _get_item_type(item: Node) -> String:
	if item and item.has_method("get_item_type"):
		return str(item.get_item_type())
	if "item_type" in item:
		return str(item.item_type)
	return ""

func _get_item_id(item: Node) -> String:
	if item and item.has_method("get_item_id"):
		return str(item.get_item_id())
	if "item_id" in item:
		return str(item.item_id)
	return ""

func _find_player_holding(item: Node) -> Node:
	# Attempts to find a player node that currently references this carried item.
	# This is best-effort; if your player script differs, adjust accordingly.
	var parent := item.get_parent()
	var hops := 0
	while parent and hops < 5:
		if parent.has_method("get_carried_item") and parent.has_method("clear_carried_item"):
			return parent
		parent = parent.get_parent()
		hops += 1
	return null

func _ensure_area_shape_size() -> void:
	if not _use_area:
		return
	for child in _use_area.get_children():
		var cs := child as CollisionShape3D
		if cs and cs.shape is BoxShape3D:
			(cs.shape as BoxShape3D).size = area_size
			if debug_log:
				_dbg("Adjusted UseArea BoxShape to %s" % str(area_size))
			return

func _ensure_pivot() -> void:
	# Resolve pivot or create one and migrate mesh/collision under it while preserving world transforms
	if pivot_path != NodePath(""):
		_pivot = get_node_or_null(pivot_path) as Node3D
	else:
		_pivot = get_node_or_null("VentPivot") as Node3D
	if _pivot == null and auto_create_pivot:
		_pivot = Node3D.new()
		_pivot.name = "VentPivot"
		add_child(_pivot)
		# Find typical children to move under pivot
		var to_move: Array = []
		for child in get_children():
			if child == _pivot:
				continue
			if child is MeshInstance3D or child is CollisionShape3D:
				to_move.append(child)
		# Reparent and preserve world transforms
		for n in to_move:
			var n3d := n as Node3D
			if n3d.get_parent() == _pivot:
				continue
			var gt := n3d.global_transform
			# Properly detach from current parent before adding to pivot
			var cur_parent := n3d.get_parent()
			if cur_parent:
				cur_parent.remove_child(n3d)
			_pivot.add_child(n3d)
			n3d.global_transform = gt
		if debug_log:
			_dbg("Auto-created VentPivot and moved %d children" % to_move.size())

func _dbg(msg: String) -> void:
	print("[VentCover:%s] %s" % [name, msg])

func _is_human_player(node: Node) -> bool:
	return node is CharacterBody3D

func _get_player_camera(player: Node) -> Camera3D:
	var cam: Camera3D = null
	if "camera_3d" in player:
		cam = player.camera_3d
		if cam:
			return cam
	cam = player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		return cam
	var pivot := player.get_node_or_null("CameraPivot")
	if pivot:
		cam = pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			return cam
	# As a last resort, look for any Camera3D child
	for c in player.get_children():
		if c is Camera3D:
			return c
	return null

func _is_crosshair_on_self(player: Node) -> bool:
	var cam := _get_player_camera(player)
	if cam == null or not cam.current:
		return false
	var vp := cam.get_viewport()
	if vp == null:
		return false
	var center := vp.get_visible_rect().size * 0.5
	var origin := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var to := origin + dir * aim_max_distance
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, to)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.exclude = [player]
	var res := space.intersect_ray(params)
	if res.is_empty():
		return false
	var collider: Node = res.get("collider") as Node
	if collider == null:
		return false
	var n := collider
	if self == n or self.is_ancestor_of(n):
		return true
	if _pivot and _pivot.is_ancestor_of(n):
		return true
	return false
