extends CharacterBody3D

@export var move_speed: float = 8.0
@export var sprint_multiplier: float = 1.6
@export var jump_velocity: float = 5.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var gravity_fall_multiplier: float = 1.6
@export var gravity_low_jump_multiplier: float = 2.2
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.15
@export var accel_speed: float = 12.0
@export var decel_speed: float = 16.0
@export var camera_smooth_speed: float = 12.0
@export var camera_instant_aim: bool = true  # If true, camera exactly matches mouse without smoothing
# Limit camera pitch to avoid looking too far down into the model
@export_range(-89.0, 89.0) var min_pitch_deg: float = -80.0 # up limit
@export_range(-89.0, 89.0) var max_pitch_deg: float = 60.0  # down limit (reduced to prevent clipping)

@export var look_sensitivity_mouse: float = 0.12
@export var look_sensitivity_pad: float = 2.0
@export var invert_y: bool = false

@export var run_speed_threshold: float = 6.0
@export var idle_anim_candidates: PackedStringArray = ["Idle", "idle", "Idle01"]
@export var walk_anim_candidates: PackedStringArray = ["Walk", "walk", "WalkForward"]
@export var run_anim_candidates: PackedStringArray = ["Run", "run", "Sprint"]
# If intent is high but actual movement is near zero due to a wall, treat as idle
@export var blocked_idle_speed_threshold: float = 0.10
@export var blocked_intent_threshold: float = 0.40

@export var carry_offset: Vector3 = Vector3(0.4, 1.3, 0.6)

@export var run_anim_name: String = "Run"

# --- Carry / Pickup settings (mirrors car player basics) ---
@export var pickup_radius: float = 2.5
@export var interact_range: float = 4.5
@export var instant_center_on_release: bool = true

@export var show_crosshair: bool = true
@export var crosshair_scan_interval: float = 0.08 # seconds between crosshair raycasts (0 = every frame)

@export var safe_record_interval: float = 0.75
@export var unstuck_speed_threshold: float = 0.25
@export var unstuck_input_threshold: float = 0.4
@export var unstuck_min_time: float = 1.25
@export var unstuck_upward_boost: float = 4.0
@export var unstuck_forward_nudge: float = 2.5

@export var animation_player_path: NodePath

@export_enum("freeze", "slow_loop") var single_move_idle_mode: String = "slow_loop" # idle handling when only one move anim exists

@export var single_move_min_move_speed: float = 0.02
@export var single_move_min_play_speed: float = 0.9
@export var single_move_max_play_speed: float = 1.25
@export var force_run_replay_if_stalled: bool = true

@export var scale_multiplier: float = 2.0  # resized human (visual only)
@export var carry_offset_scale: float = 1.0

@export var switch_fade_in_time: float = 0.25
@export var switch_fade_color: Color = Color(0, 0, 0, 1.0)

# --- Footstep SFX ---
@export var footstep_enabled: bool = true
@export var footstep_walk_interval: float = 0.45
@export var footstep_run_interval: float = 0.30
@export var footstep_min_planar_speed: float = 0.7
@export var footstep_streams: Array[AudioStream] = []
@export var footstep_streams_run: Array[AudioStream] = []
@export var footstep_volume_db: float = -6.0
@export var footstep_pitch_base: float = 1.0
@export var footstep_pitch_jitter: float = 0.08

var carried_item: Node3D = null  # NOTE: Ensure only one carried_item variable exists.
# If a duplicate 'var carried_item' was added below during earlier edits, it is removed/commented out now to fix parser error.
# (If you still see an error, search the file for 'var carried_item' and keep only the first definition.)

var _pivot: Node3D
var _cam: Camera3D
var _carry_point: Node3D
var _anim_player: AnimationPlayer = null
var _model_root: Node3D
var _crosshair: Control

var _vel: Vector3
var _yaw: float = 0.0
var _pitch: float = 0.0
var _look_x: float = 0.0
var _look_y: float = 0.0

var _idle_anim: StringName
var _walk_anim: StringName
var _run_anim: StringName

var _rc_player_path: NodePath
var _switcher: Node = null
var _controls_enabled: bool = true

var _safe_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_safe_pos: Vector3
var _have_safe: bool = false

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _smoothed_yaw: float = 0.0
var _smoothed_pitch: float = 0.0

var _last_crosshair_target: Node = null
var _crosshair_scan_t: float = 0.0

var _current_anim: StringName = StringName()
var _single_move_anim_mode: bool = false
var _missing_anim_search_timer: float = 0.0

var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null

# Footsteps internals
var _footstep_player: AudioStreamPlayer3D = null
var _footstep_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready():
	_pivot = $Pivot
	_cam = $Pivot/Camera3D
	_carry_point = $CarryPoint
	_model_root = $ModelRoot
	# Apply visual scaling only (do NOT alter speeds/physics so gameplay stays same)
	if scale_multiplier != 1.0:
		scale = Vector3.ONE * scale_multiplier
		# Optionally adjust carry offset just for hand alignment
		carry_offset *= scale_multiplier * carry_offset_scale
	_carry_point.position = carry_offset
	_anim_player = _model_root.get_node_or_null("AnimationPlayer")
	if _anim_player == null:
		var root_node = _model_root.get_node_or_null("root")
		if root_node:
			_anim_player = root_node.get_node_or_null("AnimationPlayer")
	if _anim_player and run_anim_name != "" and _anim_player.has_animation(run_anim_name):
		_run_anim = run_anim_name
	_find_anim_player()
	add_to_group("human_player")
	add_to_group("player")
	if show_crosshair:
		_create_crosshair()
	_switcher = get_node_or_null("/root/PlayerSwitcher")
	if _switcher:
		_switcher.connect("active_changed", Callable(self, "_on_active_changed"))
	_on_active_changed(_switcher.active if _switcher else &"human")
	_resolve_anim_names()
	# Footsteps setup
	_rng.randomize()
	_ensure_footstep_player()

func _process(delta):
	_apply_look(delta)
	if not _controls_enabled or not show_crosshair:
		return
	# Throttle crosshair raycasts to reduce CPU
	_crosshair_scan_t -= delta
	if crosshair_scan_interval <= 0.0 or _crosshair_scan_t <= 0.0:
		var target = _raycast_interact_target()
		if target != _last_crosshair_target:
			_update_crosshair_state(target)
			_last_crosshair_target = target
		_crosshair_scan_t = max(0.0, crosshair_scan_interval)

func _physics_process(delta):
	# Always simulate physics so the character continues moving/falling even when controls are disabled
	# Attempt periodic re-scan for AnimationPlayer if missing
	if _anim_player == null:
		_missing_anim_search_timer += delta
		if _missing_anim_search_timer >= 0.5:
			_missing_anim_search_timer = 0.0
			_find_anim_player()
	# Update timers for advanced jump
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = max(0.0, _coyote_timer - delta)
	_jump_buffer_timer = max(0.0, _jump_buffer_timer - delta)
	_apply_gravity(delta)
	if _controls_enabled:
		_move_input(delta)
	else:
		# No player input when disabled; smoothly decelerate horizontal velocity
		_apply_deceleration(delta)
	_apply_move()
	# Footsteps after motion so velocity reflects latest state
	_update_footsteps(delta)
	_apply_look(delta) # ensure camera updated every frame
	_update_animation()
	if _controls_enabled:
		process_pickup_input()
		process_drop_input()
	_update_carried_item_transform()
	_update_safe_and_unstuck(delta)
	# Crosshair highlight now handled in _process for per-frame responsiveness

# --- Public API ---
func set_rc_player_path(p: NodePath) -> void:
	_rc_player_path = p

func set_active_camera(active: bool) -> void:
	if _cam:
		_cam.current = active
	if show_crosshair:
		_set_crosshair_visible(active)
	# Lock mouse when human player is active; release when inactive
	if active:
		_lock_mouse()
	else:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_control_enabled(flag: bool) -> void:
	_controls_enabled = flag
	set_process(flag)
	set_process_input(flag)
	# Keep physics running so the human continues to fall/settle even when inactive
	set_physics_process(true)

# --- Input ---
func _input(event):
	if not _controls_enabled: return
	if event is InputEventMouseMotion:
		var invert_factor = -1.0 if invert_y else 1.0
		_look_x -= event.relative.x * look_sensitivity_mouse * 0.01
		_look_y -= event.relative.y * look_sensitivity_mouse * 0.01 * invert_factor
	if event is InputEventJoypadMotion:
		var inv = -1.0 if invert_y else 1.0
		if event.axis == 2: # right stick X
			_look_x -= event.axis_value * look_sensitivity_pad * 0.02
		elif event.axis == 3: # right stick Y
			_look_y -= event.axis_value * look_sensitivity_pad * 0.02 * inv
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_SPACE:
		_jump_buffer_timer = jump_buffer_time
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB:
		if _switcher and _controls_enabled:
			var target := &"rc"
			_switcher.set_active(target)

func _lock_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_look(delta):
	# Accumulate target angles directly from input deltas
	_yaw = wrapf(_yaw + _look_x, -PI, PI)
	# Clamp pitch using configurable limits to prevent looking too far down into the model
	var min_pitch := deg_to_rad(min_pitch_deg)
	var max_pitch := deg_to_rad(max_pitch_deg)
	_pitch = clamp(_pitch + _look_y, min_pitch, max_pitch)
	if camera_instant_aim:
		# Instant: no smoothing, perfect 1:1 stop with mouse
		rotation.y = _yaw
		if _pivot:
			_pivot.rotation.x = _pitch
		_smoothed_yaw = _yaw
		_smoothed_pitch = _pitch
	else:
		# Smooth toward target for softer feel
		var smooth_t = 1.0 - exp(-camera_smooth_speed * delta)
		_smoothed_yaw = lerp_angle(_smoothed_yaw, _yaw, smooth_t)
		_smoothed_pitch = lerp(_smoothed_pitch, _pitch, smooth_t)
		rotation.y = _smoothed_yaw
		if _pivot:
			_pivot.rotation.x = _smoothed_pitch
	# If smoothing off, do not decay deltas artificially (prevents lag). If smoothing on, gently decay.
	if not camera_instant_aim:
		_look_x = lerp(_look_x, 0.0, delta * 10.0)
		_look_y = lerp(_look_y, 0.0, delta * 10.0)
	else:
		# Consume deltas immediately for instant response
		_look_x = 0.0
		_look_y = 0.0

# --- Movement ---
func _apply_gravity(delta):
	# Advanced jump & fall tuning
	var g = gravity
	if not is_on_floor():
		if velocity.y < 0.0:
			g *= gravity_fall_multiplier
		elif velocity.y > 0.0 and not Input.is_action_pressed("jump"):
			g *= gravity_low_jump_multiplier
		_vel.y -= g * delta
	else:
		_vel.y = 0.0
	# Consume buffered jump if possible
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_vel.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

func _move_input(delta):
	var move_vec = Vector3.ZERO
	var f = -transform.basis.z
	var r = transform.basis.x
	if Input.is_action_pressed("forward"):
		move_vec += f
	if Input.is_action_pressed("back"):
		move_vec -= f
	if Input.is_action_pressed("right"):
		move_vec += r
	if Input.is_action_pressed("left"):
		move_vec -= r
	move_vec.y = 0
	var has_input = move_vec.length() > 0.001
	if has_input:
		move_vec = move_vec.normalized()
	var target_speed = move_speed
	if Input.is_action_pressed("sprint"):
		target_speed *= sprint_multiplier
	var target_planar = Vector2(move_vec.x, move_vec.z) * (target_speed if has_input else 0.0)
	var current_planar = Vector2(_vel.x, _vel.z)
	var rate = accel_speed if has_input else decel_speed
	var t = 1.0 - exp(-rate * delta)
	current_planar = current_planar.lerp(target_planar, t)
	_vel.x = current_planar.x
	_vel.z = current_planar.y

# When controls are disabled, decelerate horizontally without reading input
func _apply_deceleration(delta: float) -> void:
	var current_planar = Vector2(_vel.x, _vel.z)
	var t = 1.0 - exp(-decel_speed * delta)
	var dec = current_planar.lerp(Vector2.ZERO, t)
	_vel.x = dec.x
	_vel.z = dec.y

func _apply_move():
	velocity = _vel
	move_and_slide()

# --- Footsteps ---
func _ensure_footstep_player() -> void:
	if _footstep_player and is_instance_valid(_footstep_player):
		return
	# Reuse an existing child named "Footsteps" if present
	var existing := get_node_or_null("Footsteps")
	if existing and existing is AudioStreamPlayer3D:
		_footstep_player = existing
		return
	_footstep_player = AudioStreamPlayer3D.new()
	_footstep_player.name = "Footsteps"
	_footstep_player.unit_size = 1.0
	_footstep_player.attenuation_filter_cutoff_hz = 1000.0
	_footstep_player.bus = "Master" # change to "SFX" if you use a dedicated bus
	add_child(_footstep_player)

func _update_footsteps(delta: float) -> void:
	if not footstep_enabled:
		return
	if _footstep_player == null:
		_ensure_footstep_player()
		if _footstep_player == null:
			return
	# Only when human is the active pawn (avoid sounds from offscreen pawn)
	if not _controls_enabled:
		return
	# Must be on floor and moving at least a minimum speed
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or planar_speed < footstep_min_planar_speed:
		# Let timer catch up so first step triggers shortly after landing/moving
		_footstep_timer = min(_footstep_timer, 0.1)
		return
	var sprinting := Input.is_action_pressed("sprint")
	var interval := footstep_run_interval if sprinting else footstep_walk_interval
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_play_footstep(sprinting)
		_footstep_timer = interval

func _play_footstep(sprinting: bool) -> void:
	var options: Array[AudioStream] = []
	if sprinting and footstep_streams_run.size() > 0:
		options = footstep_streams_run
	else:
		options = footstep_streams
	if options.size() == 0:
		return
	var idx := _rng.randi_range(0, options.size() - 1)
	var stream: AudioStream = options[idx]
	if stream == null:
		return
	_footstep_player.stop()
	_footstep_player.stream = stream
	var pitch := footstep_pitch_base + _rng.randf_range(-footstep_pitch_jitter, footstep_pitch_jitter)
	_footstep_player.pitch_scale = max(0.01, pitch)
	_footstep_player.volume_db = footstep_volume_db
	_footstep_player.play()

# --- Model & Animations ---
func _resolve_anim_names():
	if _anim_player == null:
		return
	# Ensure walk and run names are set only once or if animations changed
	if _anim_player == null:
		return
	# Attempt to find idle, walk, run from candidate lists
	_idle_anim = _find_first_anim(idle_anim_candidates)
	_walk_anim = _find_first_anim(walk_anim_candidates)
	_run_anim = _find_first_anim(run_anim_candidates)
	if _walk_anim != StringName():
		_set_anim_loop_linear(_walk_anim) # Ensure walk animation loops at runtime
	if _walk_anim == StringName() and _idle_anim == StringName() and _run_anim != StringName():
		_single_move_anim_mode = true

func _find_first_anim(list: PackedStringArray) -> StringName:
	for anim_name in list:
		if _anim_player.has_animation(anim_name):
			return StringName(anim_name)
	return StringName()

func _set_anim_loop_linear(anim_name: StringName) -> void:
	if _anim_player == null or anim_name == StringName():
		return
	if _anim_player.has_animation(anim_name):
		var anim: Animation = _anim_player.get_animation(anim_name)
		if anim and anim.loop_mode != Animation.LOOP_LINEAR:
			anim.loop_mode = Animation.LOOP_LINEAR

func _update_animation():
	if _anim_player == null:
		return
	# Determine actual vs intended planar speeds
	var actual_spd := Vector2(velocity.x, velocity.z).length()
	var intent_spd := Vector2(_vel.x, _vel.z).length()
	var spd := actual_spd
	# Consider the player blocked when pushing into a wall while grounded
	var blocked := is_on_floor() and intent_spd > blocked_intent_threshold and actual_spd < blocked_idle_speed_threshold and is_on_wall()
	# Single animation (Run only) mode handling
	if _single_move_anim_mode:
		var moving := (not blocked) and spd > single_move_min_move_speed
		if moving:
			# Always ensure correct animation is playing & not stalled
			if _anim_player.current_animation != _run_anim:
				if _anim_player.has_animation(_run_anim):
					_anim_player.play(_run_anim)
					_current_anim = _run_anim
			elif not _anim_player.is_playing():
				_anim_player.play(_run_anim)
			# Optional: enforce loop flag if resource not set to loop
			if force_run_replay_if_stalled:
				if _anim_player.has_animation(_run_anim):
					var pos = _anim_player.current_animation_position
					var anim_len = _anim_player.current_animation_length
					# If non-looping and we reached end, restart (Godot 4: check Animation.loop_mode)
					var anim_res: Animation = _anim_player.get_animation(_run_anim)
					var is_loop := anim_res != null and anim_res.loop_mode != Animation.LOOP_NONE
					if anim_len > 0.0 and pos >= anim_len - 0.01 and not is_loop:
						_anim_player.play(_run_anim)
			# Speed scale based on movement speed (clamped)
			var speed_factor: float = clampf(spd / move_speed, 0.6, 1.0)
			# Map into configured min/max playback range
			var play_scale: float = lerp(single_move_min_play_speed, single_move_max_play_speed, (speed_factor - 0.6) / 0.4)
			play_scale = clampf(play_scale, single_move_min_play_speed, single_move_max_play_speed)
			_anim_player.speed_scale = play_scale
		else:
			# Idle handling (includes blocked case)
			if _anim_player.current_animation != _run_anim:
				if _anim_player.has_animation(_run_anim):
					_anim_player.play(_run_anim)
					_current_anim = _run_anim
			if single_move_idle_mode == 'freeze':
				if _anim_player.speed_scale != 0.0:
					_anim_player.speed_scale = 0.0
					_anim_player.seek(0.0, true)
			else:
				# Slow loop keeps a gentle motion so animation never appears stopped
				var idle_scale: float = 0.3
				if abs(_anim_player.speed_scale - idle_scale) > 0.01:
					_anim_player.speed_scale = idle_scale
		return
	# --- Multi-animation logic ---
	var sprinting := Input.is_action_pressed('sprint')
	var target: StringName = StringName()
	if blocked:
		# Force idle when pushing into a wall
		target = _idle_anim if _idle_anim != StringName() else (_walk_anim if _walk_anim != StringName() else _run_anim)
	elif sprinting and _run_anim != StringName() and spd > run_speed_threshold * 0.55:
		target = _run_anim
	elif spd > 0.25 and _walk_anim != StringName():
		target = _walk_anim
	elif spd > 0.25 and _walk_anim == StringName() and _run_anim != StringName():
		target = _run_anim
	else:
		target = _idle_anim if _idle_anim != StringName() else (_walk_anim if _walk_anim != StringName() else _run_anim)
	if target != StringName() and target != _current_anim:
		if _anim_player.has_animation(target):
			_anim_player.play(target)
			_anim_player.speed_scale = 1.0
			_current_anim = target

# Play idle animation explicitly (used when switching away from human)
func _play_idle_now() -> void:
	if _anim_player == null:
		return
	# Ensure we have resolved names once
	if _idle_anim == StringName() and _walk_anim == StringName() and _run_anim == StringName():
		_resolve_anim_names()
	var target: StringName = _idle_anim if _idle_anim != StringName() else (_walk_anim if _walk_anim != StringName() else _run_anim)
	if target != StringName() and _anim_player.has_animation(target):
		_anim_player.play(target)
		_anim_player.speed_scale = 1.0
		_current_anim = target

# --- Pickup / Carry System (ported from car player simplified) ---
func process_pickup_input():
	if Input.is_action_just_pressed("interact"):
		var look_target: Node3D = _raycast_pickup_item()
		if carried_item:
			# First try using carried item on what we're looking at
			if _try_use_carried_on_target():
				return
			# Allow swapping to a looked-at item (or fallback nearest)
			if not look_target:
				look_target = _get_nearest_pickup_item()
			if look_target and look_target != carried_item:
				_drop_item()
				_pick_up_item(look_target)
		else:
			# Pick up what we're looking at; fallback to nearest sphere search
			if not look_target:
				look_target = _get_nearest_pickup_item()
			if look_target:
				_pick_up_item(look_target)

func _raycast_pickup_item() -> Node3D:
	# Raycast from camera forward to find a pickup_item in view
	if not _cam:
		return null
	var from: Vector3 = _cam.global_transform.origin
	var to: Vector3 = from + -_cam.global_transform.basis.z * interact_range
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.has("collider"):
		var n: Node = hit["collider"]
		var depth := 0
		while n and depth < 5:
			if n is Node3D and n.is_in_group("pickup_item"):
				return n
			n = n.get_parent()
			depth += 1
	return null

func process_drop_input():
	if Input.is_action_just_pressed("drop") and carried_item:
		_drop_item()

func _get_nearest_pickup_item() -> Node3D:
	var nearest: Node3D = null
	var min_d = pickup_radius
	for n in get_tree().get_nodes_in_group("pickup_item"):
		if not n is Node3D: continue
		if n.has_method("is_carried") and n.is_carried():
			continue
		if n.has_method("can_be_picked") and not n.can_be_picked():
			continue
		var d = global_position.distance_to(n.global_position)
		if d <= pickup_radius and d < min_d:
			nearest = n
			min_d = d
	return nearest

func _pick_up_item(item: Node3D):
	if carried_item: return
	carried_item = item
	if item.has_method("on_picked_up"):
		item.on_picked_up(self, _carry_point)
	else:
		if item.has_method("set_physics_process"): item.set_physics_process(false)
		if item.has_method("set_process"): item.set_process(false)
		item.reparent(_carry_point)
		item.transform.origin = Vector3.ZERO

func _pick_up_item_generic(item: Node):
	# (Renamed from duplicate _pick_up_item)
	if item == null or carried_item:
		return
	carried_item = item
	if item.has_method("on_picked_up"):
		item.on_picked_up(self, _carry_point)
	else:
		item.reparent(_carry_point)
		if item is Node3D:
			item.transform.origin = Vector3.ZERO

func _drop_item():
	if not carried_item: return
	var item := carried_item
	if item.has_method("on_dropped"):
		item.on_dropped(self)
	else:
		var world = item.global_transform
		item.reparent(get_parent())
		item.global_transform = world
	carried_item = null
	_place_item_on_ground(item)

func _drop_carried_item():
	if not carried_item:
		return
	var itm = carried_item
	carried_item = null
	if itm.has_method("on_dropped"):
		itm.on_dropped(self)
	else:
		var wt = itm.global_transform
		itm.reparent(get_parent())
		itm.global_transform = wt

func _place_item_on_ground(item: Node3D):
	if not is_instance_valid(item): return
	var forward := -transform.basis.z.normalized()
	var base_pos := global_transform.origin + forward * 1.2 + Vector3.UP * 1.2
	item.global_position = base_pos
	var space := get_world_3d().direct_space_state
	var from := base_pos
	var to := base_pos - Vector3.UP * 8.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude := []
	if self is CollisionObject3D: exclude.append(self.get_rid())
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit and hit.has("position"):
		item.global_position = hit["position"] + Vector3.UP * 0.05

func _update_carried_item_transform():
	if carried_item and carried_item.get_parent() == _carry_point and not carried_item.has_method("on_picked_up"):
		carried_item.transform.origin = Vector3.ZERO

func _try_use_carried_on_target() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_transform.origin + Vector3.UP * 1.3
	var to := from + -transform.basis.z.normalized() * interact_range
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var excl := []
	if self is CollisionObject3D: excl.append(self.get_rid())
	q.exclude = excl
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	if hit and hit.has("collider"):
		var target: Node = hit["collider"]
		var n: Node = target
		var depth := 0
		while n and depth < 5:
			if n.has_method("try_interact"):
				if n.try_interact(self):
					return true
			n = n.get_parent()
			depth += 1
	return false

func _create_crosshair():
	if has_node("CrosshairLayer"): return
	var layer := CanvasLayer.new()
	layer.name = "CrosshairLayer"
	add_child(layer)
	var ui := Control.new()
	ui.name = "Crosshair"
	ui.set_script(load("res://scenes/scripts/ui/CrosshairUI.gd"))
	layer.add_child(ui)
	_crosshair = ui

func _set_crosshair_visible(v: bool):
	if _crosshair and _crosshair.has_method("set_crosshair_visible"):
		_crosshair.call("set_crosshair_visible", v)

func _update_crosshair_state(target: Node) -> void:
	if _crosshair and _crosshair.has_method("set_interactable_hint"):
		_crosshair.call("set_interactable_hint", target != null)

func _raycast_interact_target() -> Node3D:
	if not _cam:
		return null
	var from := _cam.global_transform.origin
	var to := from + -_cam.global_transform.basis.z * interact_range
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.has("collider"):
		var n: Node = hit["collider"]
		var depth := 0
		while n and depth < 5:
			if (n is Node3D and n.is_in_group("pickup_item")) or n.has_method("try_interact"):
				return n
			n = n.get_parent()
			depth += 1
	return null

func _update_safe_and_unstuck(delta: float) -> void:
	# Record a safe grounded position periodically
	_safe_timer += delta
	if _safe_timer >= safe_record_interval:
		_safe_timer = 0.0
		if is_on_floor():
			_last_safe_pos = global_position
			_have_safe = true
	# Movement / stuck detection
	var planar_speed = Vector2(velocity.x, velocity.z).length()
	var input_mag = 0.0
	if _controls_enabled:
		if Input.is_action_pressed("forward"): input_mag += 1.0
		if Input.is_action_pressed("back"): input_mag += 1.0
		if Input.is_action_pressed("left"): input_mag += 1.0
		if Input.is_action_pressed("right"): input_mag += 1.0
	if planar_speed < unstuck_speed_threshold and input_mag > 0:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	# Manual unstuck (only when player controls are enabled)
	if _controls_enabled and Input.is_action_just_pressed("unstuck") and _have_safe:
		global_position = _last_safe_pos + Vector3.UP * 0.05
		velocity = Vector3.ZERO
		_stuck_timer = 0.0
		return
	# Auto nudge
	if _stuck_timer >= unstuck_min_time:
		var forward = -transform.basis.z.normalized()
		velocity.y = max(velocity.y, unstuck_upward_boost)
		velocity.x += forward.x * unstuck_forward_nudge
		velocity.z += forward.z * unstuck_forward_nudge
		_stuck_timer = 0.0

func _switch_to_car() -> void:
	var car: Node = null
	if _rc_player_path != NodePath("") and has_node(_rc_player_path):
		car = get_node(_rc_player_path)
	else:
		var cands = get_tree().get_nodes_in_group("rc_player")
		if cands.size() > 0:
			car = cands[0]
	if car:
		if car.has_method("set_control_enabled"):
			car.set_control_enabled(true)
		if car.has_method("set_active_camera"):
			car.set_active_camera(true)
		set_control_enabled(false)
		set_active_camera(false)
		_play_idle_now() # ensure human shows idle when switching to car
		var ps := get_node_or_null("/root/PlayerSwitcher")
		if ps and ps.has_method("set_active"):
			ps.set_active(&"rc")

func _on_active_changed(which: StringName):
	var make_active := which == &"human"
	set_control_enabled(make_active)
	set_active_camera(make_active)
	if make_active:
		_play_switch_fade_in()
	else:
		_play_idle_now() # play idle when switching to car (human inactive)

func _ensure_fade_overlay() -> void:
	if _fade_rect and is_instance_valid(_fade_rect):
		return
	var root := get_tree().root
	if _fade_layer == null or not is_instance_valid(_fade_layer):
		_fade_layer = CanvasLayer.new()
		_fade_layer.name = "SwitchFadeLayer_Human"
		_fade_layer.layer = 128
		root.add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.color = switch_fade_color
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fade_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fade_layer.add_child(_fade_rect)
	# Fill viewport
	_fade_rect.custom_minimum_size = root.size
	_fade_rect.anchor_left = 0
	_fade_rect.anchor_top = 0
	_fade_rect.anchor_right = 1
	_fade_rect.anchor_bottom = 1
	_fade_rect.offset_left = 0
	_fade_rect.offset_top = 0
	_fade_rect.offset_right = 0
	_fade_rect.offset_bottom = 0

func _play_switch_fade_in() -> void:
	_ensure_fade_overlay()
	if _fade_rect == null:
		return
	_fade_rect.visible = true
	_fade_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 0.0, switch_fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.finished.connect(Callable(self, "_cleanup_fade_overlay"))

func _cleanup_fade_overlay() -> void:
	if _fade_rect:
		_fade_rect.visible = false
		_fade_rect.queue_free()
		_fade_rect = null
	if _fade_layer:
		_fade_layer.queue_free()
		_fade_layer = null

func _find_anim_player() -> void:
	if animation_player_path != NodePath(""):
		_anim_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _anim_player:
		return
	# Try common child names
	var try_names = ["AnimationPlayer", "AnimPlayer", "Anim"]
	for n in try_names:
		var candidate = get_node_or_null(n)
		if candidate and candidate is AnimationPlayer:
			_anim_player = candidate
			return
	# Try model root if defined earlier
	if Engine.has_singleton("SceneTree" ):
		pass # placeholder to avoid tool stripping context
	# Fallback: breadth-first search first AnimationPlayer in descendants
	var q: Array = []
	for c in get_children(): q.append(c)
	while q.size() > 0 and _anim_player == null:
		var node = q.pop_front()
		if node is AnimationPlayer:
			_anim_player = node
			break

func debug_force_anim_scan():
	_anim_player = null
	_find_anim_player()
	if _anim_player:
		_resolve_anim_names()

func get_carried_item():
	# Primary accessor used by doors / interactables
	if carried_item and is_instance_valid(carried_item):
		return carried_item
	# Fallback: look under carry point for first child that looks like an item
	if _carry_point:
		for c in _carry_point.get_children():
			if c is Node3D:
				return c
	return null

func clear_carried_item() -> void:
	carried_item = null
