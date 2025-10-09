extends CharacterBody3D

const WORLD_LAYER := 1 << 0
const HUMAN_LAYER := 1 << 1
const CAR_LAYER := 1 << 2
const PUSHABLE_LAYER := 1 << 3 # New layer for pushable dynamic objects

@export var move_speed: float = 8.0
@export var sprint_multiplier: float = 1.6
@export var jump_velocity: float = 4.2
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var gravity_fall_multiplier: float = 1.6
@export var gravity_low_jump_multiplier: float = 2.2
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.15
@export var accel_speed: float = 12.0
@export var decel_speed: float = 16.0
@export var camera_smooth_speed: float = 12.0
@export var camera_instant_aim: bool = true
@export_range(-89.0, 89.0) var min_pitch_deg: float = -80.0
@export_range(-89.0, 89.0) var max_pitch_deg: float = 60.0
@export var look_sensitivity_mouse: float = 0.12
@export var look_sensitivity_pad: float = 2.0
@export var invert_y: bool = false
@export var run_speed_threshold: float = 6.0
@export var idle_anim_candidates: PackedStringArray = ["Idle", "idle", "Idle01"]
@export var walk_anim_candidates: PackedStringArray = ["Walk", "walk", "WalkForward"]
@export var run_anim_candidates: PackedStringArray = ["Run", "run", "Sprint"]
@export var blocked_idle_speed_threshold: float = 0.10
@export var blocked_intent_threshold: float = 0.40
@export var carry_offset: Vector3 = Vector3(0.4, 1.3, 0.6)
@export var carry_use_bone: bool = true
@export var carry_bone_name: String = "RightHand"
@export var carry_bone_offset: Vector3 = Vector3(0.08, 0.02, 0.0)
@export var carry_bone_rotation_deg: Vector3 = Vector3(0, 0, 0)
@export var run_anim_name: String = "Run"
@export var pickup_radius: float = 2.5
@export var interact_range: float = 4.5
@export var instant_center_on_release: bool = true
@export var show_crosshair: bool = true
@export var crosshair_scan_interval: float = 0.08
@export var safe_record_interval: float = 0.75
@export var unstuck_speed_threshold: float = 0.25
@export var unstuck_input_threshold: float = 0.4
@export var unstuck_min_time: float = 1.25
@export var unstuck_upward_boost: float = 4.0
@export var unstuck_forward_nudge: float = 2.5
@export var animation_player_path: NodePath
@export_enum("freeze", "slow_loop") var single_move_idle_mode: String = "slow_loop"
@export var single_move_min_move_speed: float = 0.02
@export var single_move_min_play_speed: float = 0.9
@export var single_move_max_play_speed: float = 1.25
@export var force_run_replay_if_stalled: bool = true
@export var scale_multiplier: float = 3.0
@export var carry_offset_scale: float = 1.0
@export var switch_fade_in_time: float = 0.25
@export var switch_fade_color: Color = Color(0, 0, 0, 1.0)
@export var footstep_enabled: bool = true
@export var footstep_walk_interval: float = 0.45
@export var footstep_run_interval: float = 0.30
@export var footstep_min_planar_speed: float = 0.7
@export var footstep_streams: Array[AudioStream] = []
@export var footstep_streams_run: Array[AudioStream] = []
@export var footstep_volume_db: float = 0.0
@export var footstep_pitch_base: float = 1.0
@export var footstep_pitch_jitter: float = 0.08
@export var carry_item_offset: Vector3 = Vector3(0, -0.05, 0)
@export var carry_item_rotation_deg: Vector3 = Vector3(0, 0, 0)
@export var carry_debug_visual: bool = false
@export var crouch_speed_multiplier: float = 0.45
@export var crouch_transition_time: float = 0.18
@export var crouch_height_scale: float = 0.75 # was 0.55 (less drastic crouch)
@export var crouch_camera_drop: float = 0.4 # was 0.7 (smaller camera drop)
@export var crouch_toggle: bool = false
@export var crouch_anim_candidates: PackedStringArray = ["CrouchIdle", "crouch_idle", "Crouch"]
@export var crouch_walk_anim_candidates: PackedStringArray = ["CrouchWalk", "crouch_walk"]
@export var crouch_clearance_margin: float = 0.05
@export var crouch_use_shape_check: bool = true
@export var crouch_debug: bool = false
@export var debug_drop_logs: bool = true
# Stair/step assist (climb small steps without jumping)
@export var step_assist_enabled: bool = true
@export var step_max_height: float = 0.45
@export var step_check_forward_distance: float = 0.6
@export var step_up_boost: float = 3.0
# When true, step assist only works while inside one or more StepAssistArea(s)
@export var step_assist_requires_area: bool = false

# --- Human vision overlay settings ---
@export var human_vision_enabled: bool = false
@export var vision_vignette_strength: float = 0.0
@export var vision_vignette_softness: float = 0.2
@export var vision_distortion: float = 0.0
@export var vision_chromatic: float = 0.0
@export var vision_grain: float = 0.0
var _vision_rect: ColorRect = null

var carried_item: Node3D = null
var _pivot: Node3D
var _cam: Camera3D
var _carry_point: Node3D
var _anim_player: AnimationPlayer = null
var _model_root: Node3D
var _crosshair: Control
var _skeleton: Skeleton3D = null
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
var _footstep_player: AudioStreamPlayer3D = null
var _footstep_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _attempted_auto_hand_bone: bool = false
var _carry_bone_bound: bool = false
var _carry_debug_marker: Node3D = null
var _is_crouching: bool = false
var _crouch_tween: Tween = null
var _stand_camera_y: float = 0.0
var _crouch_camera_y: float = 0.0
var _crouch_idle_anim: StringName
var _crouch_walk_anim: StringName
var _standing_capsule_height: float = -1.0
var _standing_cylinder_height: float = -1.0
var _standing_full_height: float = -1.0
var _crosshair_pause_hidden: bool = false
# Area-triggered jump timer (separate from input jump buffer)
var _area_jump_timer: float = 0.0
# Count of overlapping StepAssistArea volumes
var _step_assist_area_count: int = 0

func _ready():
	_pivot = $Pivot
	_cam = $Pivot/Camera3D
	_carry_point = get_node_or_null("CarryPoint") as Node3D
	_model_root = $ModelRoot
	if scale_multiplier != 1.0:
		scale = Vector3.ONE * scale_multiplier
		carry_offset *= scale_multiplier * carry_offset_scale
	if _carry_point:
		_carry_point.position = carry_offset
	_anim_player = _model_root.get_node_or_null("AnimationPlayer")
	if _anim_player == null:
		var root_node = _model_root.get_node_or_null("root")
		if root_node:
			_anim_player = root_node.get_node_or_null("AnimationPlayer")
	if _anim_player and run_anim_name != "" and _anim_player.has_animation(run_anim_name):
		_run_anim = run_anim_name
	_find_anim_player()
	_find_skeleton()
	_setup_carry_bone_attachment()
	add_to_group("human_player")
	add_to_group("player")
	add_to_group("players") # ensure compatibility with Pushable.gd expectation
	# --- Collision setup: avoid human <-> car pushing ---
	# Ensure Human is on HUMAN layer (and default WORLD), and do not collide with CAR layer.
	collision_layer |= (WORLD_LAYER | HUMAN_LAYER)
	collision_mask &= ~CAR_LAYER
	# Ensure we collide with pushables
	collision_mask |= PUSHABLE_LAYER
	# ---------------------------------------------------
	if show_crosshair:
		_create_crosshair()
	_switcher = get_node_or_null("/root/PlayerSwitcher")
	if _switcher:
		_switcher.connect("active_changed", Callable(self, "_on_active_changed"))
	_on_active_changed(_switcher.active if _switcher else &"human")
	_resolve_anim_names()
	_rng.randomize()
	_ensure_footstep_player()
	if _pivot:
		_stand_camera_y = _pivot.position.y
		_crouch_camera_y = _stand_camera_y - crouch_camera_drop

func _process(delta):
	_apply_look(delta)
	if carry_debug_visual:
		_debug_update_carry_anchor_marker()
	# Pause handling: hide crosshair while paused.
	if get_tree().paused:
		if _crosshair and show_crosshair and _crosshair.visible:
			_set_crosshair_visible(false)
			_crosshair_pause_hidden = true
		return
	elif _crosshair_pause_hidden and show_crosshair:
		_set_crosshair_visible(true)
		_crosshair_pause_hidden = false
	if not _controls_enabled or not show_crosshair:
		return
	_crosshair_scan_t -= delta
	if crosshair_scan_interval <= 0.0 or _crosshair_scan_t <= 0.0:
		var target = _raycast_interact_target()
		if target != _last_crosshair_target:
			_update_crosshair_state(target)
			_last_crosshair_target = target
		_crosshair_scan_t = max(0.0, crosshair_scan_interval)

func _physics_process(delta):
	if carry_use_bone and not _carry_bone_bound:
		_ensure_carry_bone_bound()
	if _anim_player == null:
		_missing_anim_search_timer += delta
		if _missing_anim_search_timer >= 0.5:
			_missing_anim_search_timer = 0.0
			_find_anim_player()
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = max(0.0, _coyote_timer - delta)
	_jump_buffer_timer = max(0.0, _jump_buffer_timer - delta)
	_area_jump_timer = max(0.0, _area_jump_timer - delta)
	_apply_gravity(delta)
	if _controls_enabled:
		_move_input(delta)
	else:
		_apply_deceleration(delta)
	# Apply step assist before moving so we can climb small steps
	_apply_step_assist(delta)
	_apply_move()
	_update_footsteps(delta)
	_apply_look(delta)
	_update_animation()
	if _controls_enabled:
		process_pickup_input()
		process_drop_input()
	_update_carried_item_transform()
	_update_safe_and_unstuck(delta)

func set_rc_player_path(p: NodePath) -> void:
	_rc_player_path = p

func set_active_camera(active: bool) -> void:
	if _cam:
		_cam.current = active
	if show_crosshair:
		_set_crosshair_visible(active)
	if active:
		_lock_mouse()
	else:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_control_enabled(flag: bool) -> void:
	_controls_enabled = flag
	set_process(flag)
	set_process_input(flag)
	set_physics_process(true)

func _input(event):
	if not _controls_enabled: return
	# Debug: log raw Q presses and the drop action state
	if debug_drop_logs and event is InputEventKey and event.pressed and event.physical_keycode == KEY_Q:
		print("[HumanPlayer] Q pressed. is_action_just_pressed('drop')=", Input.is_action_just_pressed("drop"))
	if event is InputEventMouseMotion:
		var invert_factor = -1.0 if invert_y else 1.0
		_look_x -= event.relative.x * look_sensitivity_mouse * 0.01
		_look_y -= event.relative.y * look_sensitivity_mouse * 0.01 * invert_factor
	if event is InputEventJoypadMotion:
		var inv = -1.0 if invert_y else 1.0
		if event.axis == 2:
			_look_x -= event.axis_value * look_sensitivity_pad * 0.02
		elif event.axis == 3:
			_look_y -= event.axis_value * look_sensitivity_pad * 0.02 * inv
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_SPACE:
		# Keep manual jump behavior via the input jump buffer
		_jump_buffer_timer = jump_buffer_time
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB:
		if _switcher and _controls_enabled:
			var target := &"rc"
			_switcher.set_active(target)
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_CTRL:
		if crouch_toggle:
			_set_crouch(not _is_crouching)
		else:
			_set_crouch(true)
	if event is InputEventKey and not event.pressed and event.physical_keycode == KEY_CTRL and not crouch_toggle:
		_set_crouch(false)

func _lock_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_look(delta):
	_yaw = wrapf(_yaw + _look_x, -PI, PI)
	var min_pitch := deg_to_rad(min_pitch_deg)
	var max_pitch := deg_to_rad(max_pitch_deg)
	_pitch = clamp(_pitch + _look_y, min_pitch, max_pitch)
	if camera_instant_aim:
		rotation.y = _yaw
		if _pivot: _pivot.rotation.x = _pitch
		_smoothed_yaw = _yaw
		_smoothed_pitch = _pitch
	else:
		var smooth_t = 1.0 - exp(-camera_smooth_speed * delta)
		_smoothed_yaw = lerp_angle(_smoothed_yaw, _yaw, smooth_t)
		_smoothed_pitch = lerp(_smoothed_pitch, _pitch, smooth_t)
		rotation.y = _smoothed_yaw
		if _pivot: _pivot.rotation.x = _smoothed_pitch
	if not camera_instant_aim:
		_look_x = lerp(_look_x, 0.0, delta * 10.0)
		_look_y = lerp(_look_y, 0.0, delta * 10.0)
	else:
		_look_x = 0.0
		_look_y = 0.0

func _apply_gravity(delta):
	var g = gravity
	if not is_on_floor():
		if velocity.y < 0.0:
			g *= gravity_fall_multiplier
		elif velocity.y > 0.0 and not Input.is_action_pressed("jump"):
			g *= gravity_low_jump_multiplier
		_vel.y -= g * delta
	else:
		_vel.y = 0.0
	# Accept either input-buffered jump or area-requested jump
	if (_jump_buffer_timer > 0.0 or _area_jump_timer > 0.0) and _coyote_timer > 0.0:
		_vel.y = jump_velocity
		_jump_buffer_timer = 0.0
		_area_jump_timer = 0.0
		_coyote_timer = 0.0

func _move_input(delta):
	var move_vec = Vector3.ZERO
	var f = -transform.basis.z
	var r = transform.basis.x
	if Input.is_action_pressed("forward"): move_vec += f
	if Input.is_action_pressed("back"): move_vec -= f
	if Input.is_action_pressed("right"): move_vec += r
	if Input.is_action_pressed("left"): move_vec -= r
	move_vec.y = 0
	var has_input = move_vec.length() > 0.001
	if has_input: move_vec = move_vec.normalized()
	var target_speed = move_speed
	if _is_crouching:
		target_speed *= crouch_speed_multiplier
	elif Input.is_action_pressed("sprint"):
		target_speed *= sprint_multiplier
	var target_planar = Vector2(move_vec.x, move_vec.z) * (target_speed if has_input else 0.0)
	var current_planar = Vector2(_vel.x, _vel.z)
	var rate = accel_speed if has_input else decel_speed
	var t = 1.0 - exp(-rate * delta)
	current_planar = current_planar.lerp(target_planar, t)
	_vel.x = current_planar.x
	_vel.z = current_planar.y

func _apply_deceleration(delta: float) -> void:
	var current_planar = Vector2(_vel.x, _vel.z)
	var t = 1.0 - exp(-decel_speed * delta)
	var dec = current_planar.lerp(Vector2.ZERO, t)
	_vel.x = dec.x
	_vel.z = dec.y

func _apply_move():
	velocity = _vel
	move_and_slide()

func _ensure_footstep_player() -> void:
	if _footstep_player and is_instance_valid(_footstep_player): return
	var existing := get_node_or_null("Footsteps")
	if existing and existing is AudioStreamPlayer3D:
		_footstep_player = existing
		# Ensure footsteps use the SFX bus
		_footstep_player.bus = "SFX"
		return
	_footstep_player = AudioStreamPlayer3D.new()
	_footstep_player.name = "Footsteps"
	_footstep_player.unit_size = 1.0
	_footstep_player.attenuation_filter_cutoff_hz = 1000.0
	# Route to SFX bus instead of Master
	_footstep_player.bus = "SFX"
	add_child(_footstep_player)

func _update_footsteps(delta: float) -> void:
	if not footstep_enabled: return
	if _footstep_player == null:
		_ensure_footstep_player()
		if _footstep_player == null: return
	if not _controls_enabled: return
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or planar_speed < footstep_min_planar_speed:
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
	if sprinting and footstep_streams_run.size() > 0: options = footstep_streams_run
	else: options = footstep_streams
	if options.size() == 0: return
	var idx := _rng.randi_range(0, options.size() - 1)
	var stream: AudioStream = options[idx]
	if stream == null: return
	_footstep_player.stop()
	_footstep_player.stream = stream
	var pitch := footstep_pitch_base + _rng.randf_range(-footstep_pitch_jitter, footstep_pitch_jitter)
	_footstep_player.pitch_scale = max(0.01, pitch)
	_footstep_player.volume_db = footstep_volume_db
	_footstep_player.play()

# --- Public API: allow external triggers to make the human jump ---
## Request the player to jump on next valid frame (respects coyote timing).
## If force is true, apply the jump immediately, ignoring coyote/buffer.
func request_jump(force: bool = false) -> void:
	if not _controls_enabled:
		return
	if force:
		_vel.y = jump_velocity
		_jump_buffer_timer = 0.0
		_area_jump_timer = 0.0
		_coyote_timer = 0.0
		return
	# Schedule a jump via the area-specific timer so it does not interfere with input buffer
	_area_jump_timer = max(_area_jump_timer, 0.05)

# --- Public API: Step Assist area gating ---
## Called by StepAssistArea when the player enters/exits such an area.
func step_assist_area_enter() -> void:
	_step_assist_area_count += 1

func step_assist_area_exit() -> void:
	_step_assist_area_count = max(0, _step_assist_area_count - 1)

func _resolve_anim_names():
	if _anim_player == null: return
	_idle_anim = _find_first_anim(idle_anim_candidates)
	_walk_anim = _find_first_anim(walk_anim_candidates)
	_run_anim = _find_first_anim(run_anim_candidates)
	_crouch_idle_anim = _find_first_anim(crouch_anim_candidates)
	_crouch_walk_anim = _find_first_anim(crouch_walk_anim_candidates)
	if _walk_anim != StringName(): _set_anim_loop_linear(_walk_anim)
	if _crouch_walk_anim != StringName(): _set_anim_loop_linear(_crouch_walk_anim)
	if _walk_anim == StringName() and _idle_anim == StringName() and _run_anim != StringName():
		_single_move_anim_mode = true

func _find_first_anim(list: PackedStringArray) -> StringName:
	for anim_name in list:
		if _anim_player.has_animation(anim_name): return StringName(anim_name)
	return StringName()

func _set_anim_loop_linear(anim_name: StringName) -> void:
	if _anim_player == null or anim_name == StringName(): return
	if _anim_player.has_animation(anim_name):
		var anim: Animation = _anim_player.get_animation(anim_name)
		if anim and anim.loop_mode != Animation.LOOP_LINEAR:
			anim.loop_mode = Animation.LOOP_LINEAR

func _update_animation():
	if _anim_player == null: return
	if _is_crouching:
		var planar := Vector2(velocity.x, velocity.z).length()
		var anim_to := _crouch_walk_anim if planar > 0.25 and _crouch_walk_anim != StringName() else _crouch_idle_anim
		if anim_to != StringName() and anim_to != _current_anim and _anim_player.has_animation(anim_to):
			_anim_player.play(anim_to)
			_current_anim = anim_to
		return
	var actual_spd := Vector2(velocity.x, velocity.z).length()
	var intent_spd := Vector2(_vel.x, _vel.z).length()
	var spd := actual_spd
	var blocked := is_on_floor() and intent_spd > blocked_intent_threshold and actual_spd < blocked_idle_speed_threshold and is_on_wall()
	if _single_move_anim_mode:
		var moving := (not blocked) and spd > single_move_min_move_speed
		if moving:
			if _anim_player.current_animation != _run_anim:
				if _anim_player.has_animation(_run_anim):
					_anim_player.play(_run_anim)
					_current_anim = _run_anim
			elif not _anim_player.is_playing():
				_anim_player.play(_run_anim)
			if force_run_replay_if_stalled:
				if _anim_player.has_animation(_run_anim):
					var pos = _anim_player.current_animation_position
					var anim_len = _anim_player.current_animation_length
					var anim_res: Animation = _anim_player.get_animation(_run_anim)
					var is_loop := anim_res != null and anim_res.loop_mode != Animation.LOOP_NONE
					if anim_len > 0.0 and pos >= anim_len - 0.01 and not is_loop:
						_anim_player.play(_run_anim)
			var speed_factor: float = clampf(spd / move_speed, 0.6, 1.0)
			var play_scale: float = lerp(single_move_min_play_speed, single_move_max_play_speed, (speed_factor - 0.6) / 0.4)
			play_scale = clampf(play_scale, single_move_min_play_speed, single_move_max_play_speed)
			_anim_player.speed_scale = play_scale
		else:
			if _anim_player.current_animation != _run_anim:
				if _anim_player.has_animation(_run_anim):
					_anim_player.play(_run_anim)
					_current_anim = _run_anim
			if single_move_idle_mode == 'freeze':
				if _anim_player.speed_scale != 0.0:
					_anim_player.speed_scale = 0.0
					_anim_player.seek(0.0, true)
			else:
				var idle_scale: float = 0.3
				if abs(_anim_player.speed_scale - idle_scale) > 0.01:
					_anim_player.speed_scale = idle_scale
		return
	var sprinting := Input.is_action_pressed('sprint')
	var target: StringName = StringName()
	if blocked:
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

func _play_idle_now() -> void:
	if _anim_player == null: return
	if _idle_anim == StringName() and _walk_anim == StringName() and _run_anim == StringName():
		_resolve_anim_names()
	var target: StringName = _idle_anim if _idle_anim != StringName() else (_walk_anim if _walk_anim != StringName() else _run_anim)
	if target != StringName() and _anim_player.has_animation(target):
		_anim_player.play(target)
		_anim_player.speed_scale = 1.0
		_current_anim = target

# --- Pickup / Carry ---
func process_pickup_input():
	if Input.is_action_just_pressed("interact"):
		if carried_item:
			if _try_use_carried_on_target(): return
			var look_target: Node3D = _raycast_pickup_item()
			if not look_target: look_target = _get_nearest_pickup_item()
			if look_target and look_target != carried_item:
				# Detach from car roof if this item is currently displayed there
				_detach_item_from_car_if_on_roof(look_target)
				_drop_item()
				_pick_up_item(look_target)
		else:
			var hit := _raycast_interact_target()
			if hit:
				var n: Node = hit
				var depth := 0
				while n and depth < 6:
					if n.has_method("try_interact"):
						if n.try_interact(self): return
					n = n.get_parent()
					depth += 1
			var look_target2: Node3D = _raycast_pickup_item()
			if not look_target2: look_target2 = _get_nearest_pickup_item()
			if look_target2:
				# Detach from car roof if applicable
				_detach_item_from_car_if_on_roof(look_target2)
				_pick_up_item(look_target2)

func _raycast_pickup_item() -> Node3D:
	if not _cam: return null
	var from: Vector3 = _cam.global_transform.origin
	var to: Vector3 = from + -_cam.global_transform.basis.z * interact_range
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.has("collider"):
		var n: Node = hit["collider"]
		var depth := 0
		while n and depth < 5:
			if n is Node3D and n.is_in_group("pickup_item"):
				var item := n as Node3D
				var par := item.get_parent()
				if par and par.get_parent() and par.get_parent().is_in_group("rc_player"):
					var car := par.get_parent()
					# Remove from car inventory display/array
					if car and car.has_method("inventory_remove_item"):
						car.inventory_remove_item(item)
					# If the car was actively carrying this, clear its carried pointer
					if car and car.has_method("get_carried_item") and car.get_carried_item() == item and car.has_method("clear_carried_item"):
						car.clear_carried_item()
					# Ensure the item is re-enabled for world pickup
					if item.has_method("on_removed_from_inventory"):
						item.on_removed_from_inventory(car, null)
					item.visible = true
					return item
				return item
			n = n.get_parent(); depth += 1
	return null

func process_drop_input():
	if Input.is_action_just_pressed("drop"):
		if debug_drop_logs:
			print("[HumanPlayer] drop action pressed. carried_item=", carried_item != null)
		if carried_item:
			_drop_item()
			if debug_drop_logs:
				print("[HumanPlayer] dropped carried item.")

func _get_nearest_pickup_item() -> Node3D:
	var nearest: Node3D = null
	var min_d = pickup_radius
	for n in get_tree().get_nodes_in_group("pickup_item"):
		if not n is Node3D: continue
		# Skip already carried by someone
		if n.has_method("is_carried") and n.is_carried(): continue
		var d = global_position.distance_to(n.global_position)
		if d > pickup_radius or d >= min_d: continue
		# Standard pickable gate
		var pickable := true
		if n.has_method("can_be_picked") and not n.can_be_picked():
			# Special-case: items shown on car roof have their areas disabled; allow them
			pickable = _is_item_on_car_roof(n)
		if not pickable: continue
		nearest = n
		min_d = d
	return nearest

# Returns true if the item is currently parented under the car's display/carry point hierarchy
func _is_item_on_car_roof(item: Node) -> bool:
	var p := item.get_parent()
	return p != null and p.get_parent() != null and p.get_parent().is_in_group("rc_player")

# If the item is on the car roof/inventory display, remove it from the car inventory and re-enable interaction
func _detach_item_from_car_if_on_roof(item: Node) -> bool:
	var p := item.get_parent() if item else null
	if p and p.get_parent() and p.get_parent().is_in_group("rc_player"):
		var car := p.get_parent()
		if car and car.has_method("inventory_remove_item"):
			car.inventory_remove_item(item)
		if car and car.has_method("get_carried_item") and car.get_carried_item() == item and car.has_method("clear_carried_item"):
			car.clear_carried_item()
		if item.has_method("on_removed_from_inventory"):
			item.on_removed_from_inventory(car, null)
		if item is Node3D:
			(item as Node3D).visible = true
		return true
	return false

func _ensure_carry_anchor():
	if _carry_point: return
	if carry_use_bone:
		_find_skeleton()
		_setup_carry_bone_attachment()
	if _carry_point: return
	_carry_point = Node3D.new()
	_carry_point.name = "CarryAnchor"
	add_child(_carry_point)
	_carry_point.transform = Transform3D(Basis.IDENTITY, carry_offset)

func _pick_up_item(item: Node3D):
	if carried_item: return
	_ensure_carry_anchor()
	var anchor: Node3D = _carry_point if _carry_point else self
	carried_item = item
	if item.has_method("on_picked_up"):
		item.on_picked_up(self, anchor)
	else:
		if item.has_method("set_physics_process"): item.set_physics_process(false)
		if item.has_method("set_process"): item.set_process(false)
		item.reparent(anchor)
		item.transform.origin = Vector3.ZERO
		_apply_item_alignment(item)

func _pick_up_item_generic(item: Node):
	if item == null or carried_item: return
	_ensure_carry_anchor()
	var anchor: Node3D = _carry_point if _carry_point else self
	carried_item = item
	if item.has_method("on_picked_up"):
		item.on_picked_up(self, anchor)
	else:
		item.reparent(anchor)
		if item is Node3D:
			item.transform.origin = Vector3.ZERO
			_apply_item_alignment(item)

func _apply_item_alignment(item: Node):
	if not (item is Node3D): return
	var off: Vector3 = carry_item_offset
	var rot_deg: Vector3 = carry_item_rotation_deg
	if "carry_item_offset" in item: off = item.carry_item_offset
	if "carry_item_rotation_deg" in item: rot_deg = item.carry_item_rotation_deg
	var item_basis := Basis.IDENTITY
	if rot_deg != Vector3.ZERO:
		item_basis = Basis.from_euler(Vector3(deg_to_rad(rot_deg.x),deg_to_rad(rot_deg.y),deg_to_rad(rot_deg.z)))
	(item as Node3D).transform = Transform3D(item_basis, off)

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
	if not carried_item: return
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
		if carry_debug_visual and _skeleton and _carry_point and _carry_point is BoneAttachment3D:
			var bi := _skeleton.find_bone(carry_bone_name)
			if bi != -1:
				var bone_xform := _skeleton.get_bone_global_pose(bi)
				var anchor_pos := _carry_point.global_transform.origin
				var diff := anchor_pos - bone_xform.origin
				if diff.length() > 0.02:
					print("[CarryDebug] Anchor drift from bone ", carry_bone_name, ": ", diff)

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
				if n.try_interact(self): return true
			n = n.get_parent(); depth += 1
	return false

func _create_crosshair():
	if has_node("CrosshairLayer"):
		# Ensure vision overlay exists under the same layer
		var lay := get_node("CrosshairLayer") as CanvasLayer
		_ensure_human_vision_overlay(lay)
		return
	var layer := CanvasLayer.new(); layer.name = "CrosshairLayer"; add_child(layer)
	# Create the vision overlay first so the crosshair renders above it
	_ensure_human_vision_overlay(layer)
	var ui := Control.new(); ui.name = "Crosshair"; ui.set_script(load("res://scenes/scripts/ui/CrosshairUI.gd")); layer.add_child(ui)
	_crosshair = ui

func _set_crosshair_visible(v: bool):
	if _crosshair and _crosshair.has_method("set_crosshair_visible"):
		_crosshair.call("set_crosshair_visible", v)

func _update_crosshair_state(target: Node) -> void:
	if _crosshair and _crosshair.has_method("set_interactable_hint"):
		_crosshair.call("set_interactable_hint", target != null)

func _raycast_interact_target() -> Node3D:
	if not _cam: return null
	var from := _cam.global_transform.origin
	var to := from + -_cam.global_transform.basis.z * interact_range
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.has("collider"):
		var n: Node = hit["collider"]
		var depth := 0
		while n and depth < 5:
			if (n is Node3D and n.is_in_group("pickup_item")) or n.has_method("try_interact"):
				return n
			n = n.get_parent(); depth += 1
	return null

func _update_safe_and_unstuck(delta: float) -> void:
	_safe_timer += delta
	if _safe_timer >= safe_record_interval:
		_safe_timer = 0.0
		if is_on_floor(): _last_safe_pos = global_position; _have_safe = true
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
	if _controls_enabled and Input.is_action_just_pressed("unstuck") and _have_safe:
		global_position = _last_safe_pos + Vector3.UP * 0.05
		velocity = Vector3.ZERO
		_stuck_timer = 0.0
		return
	if _stuck_timer >= unstuck_min_time:
		var forward = -transform.basis.z.normalized()
		velocity.y = max(velocity.y, unstuck_upward_boost)
		velocity.x += forward.x * unstuck_forward_nudge
		velocity.z += forward.z * unstuck_forward_nudge
		_stuck_timer = 0.0

func _switch_to_car() -> void:
	var car: Node = null
	if _rc_player_path != NodePath("") and has_node(_rc_player_path): car = get_node(_rc_player_path)
	else:
		var cands = get_tree().get_nodes_in_group("rc_player")
		if cands.size() > 0: car = cands[0]
	if car:
		if car.has_method("set_control_enabled"): car.set_control_enabled(true)
		if car.has_method("set_active_camera"): car.set_active_camera(true)
		set_control_enabled(false)
		set_active_camera(false)
		_play_idle_now()
		var ps := get_node_or_null("/root/PlayerSwitcher")
		if ps and ps.has_method("set_active"): ps.set_active(&"rc")

func _on_active_changed(which: StringName):
	var make_active := which == &"human"
	set_control_enabled(make_active)
	set_active_camera(make_active)
	if make_active:
		_play_switch_fade_in()
	else:
		_play_idle_now()
	# Toggle vision overlay visibility with active state
	_set_human_vision_visible(make_active and human_vision_enabled)

func _ensure_fade_overlay() -> void:
	if _fade_rect and is_instance_valid(_fade_rect): return
	var root := get_tree().root
	if _fade_layer == null or not is_instance_valid(_fade_layer):
		_fade_layer = CanvasLayer.new(); _fade_layer.name = "SwitchFadeLayer_Human"; _fade_layer.layer = 128; root.add_child(_fade_layer)
	_fade_rect = ColorRect.new(); _fade_rect.name = "FadeRect"; _fade_rect.color = switch_fade_color; _fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fade_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fade_layer.add_child(_fade_rect)
	_fade_rect.custom_minimum_size = root.size
	_fade_rect.anchor_left = 0; _fade_rect.anchor_top = 0; _fade_rect.anchor_right = 1; _fade_rect.anchor_bottom = 1
	_fade_rect.offset_left = 0; _fade_rect.offset_top = 0; _fade_rect.offset_right = 0; _fade_rect.offset_bottom = 0

func _play_switch_fade_in() -> void:
	_ensure_fade_overlay()
	if _fade_rect == null: return
	_fade_rect.visible = true
	_fade_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 0.0, switch_fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.finished.connect(Callable(self, "_cleanup_fade_overlay"))

func _cleanup_fade_overlay() -> void:
	if _fade_rect: _fade_rect.visible = false; _fade_rect.queue_free(); _fade_rect = null
	if _fade_layer: _fade_layer.queue_free(); _fade_layer = null

func _find_anim_player() -> void:
	if animation_player_path != NodePath(""): _anim_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _anim_player: return
	var try_names = ["AnimationPlayer", "AnimPlayer", "Anim"]
	for n in try_names:
		var candidate = get_node_or_null(n)
		if candidate and candidate is AnimationPlayer:
			_anim_player = candidate; return
	var q: Array = []
	for c in get_children(): q.append(c)
	while q.size() > 0 and _anim_player == null:
		var node = q.pop_front()
		if node is AnimationPlayer: _anim_player = node; break
		for c2 in node.get_children(): q.append(c2)

func debug_force_anim_scan():
	_anim_player = null
	_find_anim_player()
	if _anim_player: _resolve_anim_names()

func get_carried_item():
	if carried_item and is_instance_valid(carried_item): return carried_item
	if _carry_point:
		for c in _carry_point.get_children(): if c is Node3D: return c
	return null

func clear_carried_item() -> void: carried_item = null

func _find_skeleton():
	if _model_root: _skeleton = _model_root.get_node_or_null("Skeleton3D") as Skeleton3D
	if _skeleton: return
	var roots: Array = []
	if _model_root:
		roots.append(_model_root)
	else:
		roots.append(self)
	for root in roots:
		var q: Array = []
		for c in root.get_children(): q.append(c)
		while q.size() > 0 and _skeleton == null:
			var n = q.pop_front()
			if n is Skeleton3D:
				_skeleton = n
				break
			for c2 in n.get_children(): q.append(c2)

func _setup_carry_bone_attachment():
	if not carry_use_bone: return
	if _skeleton == null: return
	var bone_idx := _skeleton.find_bone(carry_bone_name)
	if bone_idx == -1: return
	var attach: BoneAttachment3D = _skeleton.get_node_or_null("CarryBoneAttachment") as BoneAttachment3D
	if attach == null:
		attach = BoneAttachment3D.new(); attach.name = "CarryBoneAttachment"; attach.bone_name = carry_bone_name; attach.use_bone_scale = true; _skeleton.add_child(attach)
	attach.process_mode = Node.PROCESS_MODE_INHERIT
	if _carry_point == null or _carry_point == attach: _carry_point = attach
	else:
		if _carry_point.get_parent() != attach:
			var keep := _carry_point.global_transform
			_carry_point.reparent(attach)
			_carry_point.global_transform = keep
	var b := Basis.IDENTITY
	if carry_bone_rotation_deg != Vector3.ZERO:
		b = Basis.from_euler(Vector3(deg_to_rad(carry_bone_rotation_deg.x),deg_to_rad(carry_bone_rotation_deg.y),deg_to_rad(carry_bone_rotation_deg.z)))
	_carry_point.transform = Transform3D(b, carry_bone_offset)
	_carry_bone_bound = true

func debug_rebind_carry_bone():
	_find_skeleton(); _setup_carry_bone_attachment()

func _ensure_carry_bone_bound():
	if _skeleton == null:
		_find_skeleton(); if _skeleton == null: return
	if _carry_bone_bound: return
	var idx := _skeleton.find_bone(carry_bone_name)
	if idx == -1 and not _attempted_auto_hand_bone:
		_attempted_auto_hand_bone = true
		var hand_candidates: Array = []
		for i in range(_skeleton.get_bone_count()):
			var bname := _skeleton.get_bone_name(i)
			var low := bname.to_lower()
			if low.find("hand") != -1 and (low.find("r") != -1 or low.find("right") != -1): hand_candidates.append(bname)
		if hand_candidates.size() == 0:
			for i in range(_skeleton.get_bone_count()):
				var bname2 := _skeleton.get_bone_name(i)
				if bname2.to_lower().find("hand") != -1: hand_candidates.append(bname2)
		if hand_candidates.size() > 0: carry_bone_name = hand_candidates[0]
	_setup_carry_bone_attachment()

func debug_list_bones():
	if _skeleton == null: _find_skeleton()
	if _skeleton == null: print("[HumanPlayer] No skeleton found."); return
	print("[HumanPlayer] Bones:")
	for i in range(_skeleton.get_bone_count()): print("  ", i, ": ", _skeleton.get_bone_name(i))

func debug_dump_carry_info():
	print("--- Carry Debug Info ---")
	print("Carry use bone:", carry_use_bone, " bone name:", carry_bone_name)
	print("Carry point node:", _carry_point, " class:", (_carry_point.get_class() if _carry_point else "null"))
	print("Item:", carried_item)
	if _skeleton:
		var bi := _skeleton.find_bone(carry_bone_name)
		print("Bone index:", bi)
		if bi != -1:
			var bone_pose := _skeleton.get_bone_global_pose(bi)
			print("Bone global origin:", bone_pose.origin)
	if _carry_point: print("Anchor global origin:", _carry_point.global_transform.origin)
	if carried_item and carried_item is Node3D: print("Item global origin:", carried_item.global_transform.origin)
	if _anim_player: print("Anim playing:", _anim_player.current_animation, " time:", _anim_player.current_animation_position)
	print("------------------------")

func _debug_update_carry_anchor_marker():
	if _carry_point == null: return
	if _carry_debug_marker == null or not is_instance_valid(_carry_debug_marker):
		var mi := MeshInstance3D.new(); mi.name = "CarryDebugMarker"; var sphere := SphereMesh.new(); sphere.radius = 0.03; sphere.height = 0.06; mi.mesh = sphere; _carry_point.add_child(mi); _carry_debug_marker = mi
	if _carry_debug_marker: _carry_debug_marker.visible = true

func debug_toggle_carry_visual(flag: bool = true):
	carry_debug_visual = flag
	if not flag and _carry_debug_marker and is_instance_valid(_carry_debug_marker): _carry_debug_marker.visible = false

func debug_force_item_reparent():
	if carried_item and _carry_point and carried_item.get_parent() != _carry_point:
		var keep := carried_item.global_transform
		carried_item.reparent(_carry_point)
		carried_item.global_transform = keep

func _set_crouch(flag: bool):
	if flag == _is_crouching: return
	if flag and not is_on_floor(): return
	if not flag and _is_crouching:
		if not _can_stand_up():
			if crouch_debug: print_debug("[HumanPlayer] Cannot stand: ceiling obstruction.")
			return
	_is_crouching = flag
	_update_crouch_camera()
	_adjust_collider_height(flag)

# --- CROUCH / STAND CLEARANCE ---
func _can_stand_up() -> bool:
	if _standing_full_height <= 0.0:
		return true
	var cs: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		for c in get_children():
			var cs2 := c as CollisionShape3D
			if cs2:
				cs = cs2
				break
	if cs == null or cs.shape == null:
		return true
	var current_full_local := 0.0
	var radius_local := 0.0
	var is_capsule := false
	var is_cylinder := false
	if cs.shape is CapsuleShape3D:
		var cap := cs.shape as CapsuleShape3D
		current_full_local = cap.height + cap.radius * 2.0
		radius_local = cap.radius
		is_capsule = true
	elif cs.shape is CylinderShape3D:
		var cyl := cs.shape as CylinderShape3D
		current_full_local = cyl.height
		if "radius" in cyl:
			radius_local = cyl.radius
		is_cylinder = true
	else:
		return true
	var scale_y := cs.global_transform.basis.get_scale().y
	var world_current_full := current_full_local * scale_y
	var world_standing_full := _standing_full_height * scale_y
	var needed_extra_world := world_standing_full - world_current_full
	if needed_extra_world <= 0.01 * scale_y:
		return true
	var exclude: Array = [get_rid()]
	var stack: Array = [self]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is CollisionObject3D:
			exclude.append(n.get_rid())
		for ch in n.get_children():
			stack.append(ch)
	if carried_item and carried_item is CollisionObject3D:
		exclude.append((carried_item as CollisionObject3D).get_rid())
	var margin_world := crouch_clearance_margin * scale_y
	var top_current_world: Vector3 = cs.global_transform.origin + Vector3.UP * (world_current_full * 0.5)
	if crouch_use_shape_check and (is_capsule or is_cylinder):
		var headroom_height: float = max(0.01, needed_extra_world - margin_world * 2.0)
		if headroom_height > 0.01:
			var headroom_shape := CylinderShape3D.new()
			headroom_shape.height = headroom_height
			headroom_shape.radius = max(0.01, radius_local * scale_y - 0.01)
			var params := PhysicsShapeQueryParameters3D.new()
			params.shape = headroom_shape
			params.transform = Transform3D(Basis.IDENTITY, top_current_world + Vector3.UP * (headroom_height * 0.5 + margin_world))
			params.exclude = exclude
			params.margin = margin_world
			var hits := get_world_3d().direct_space_state.intersect_shape(params, 8)
			if hits.size() == 0:
				return true
			elif crouch_debug:
				var names := []
				for h in hits:
					if h.has("collider"):
						var col = h["collider"]
						if col:
							names.append(col.name)
				print_debug("[Crouch] Stand blocked (headroom shape) by ", names)
			return false
	# Fallback ray
	var from := top_current_world
	var to := from + Vector3.UP * (needed_extra_world + margin_world)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = exclude
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var ok := not (hit and hit.has("collider"))
	if crouch_debug and not ok:
		print_debug("[Crouch] Ray blocked by ", (hit["collider"].name if hit.has("collider") else "?"), " from ", from, " to ", to, " needed_extra_world=", needed_extra_world)
	return ok

func _update_crouch_camera():
	if not _pivot:
		return
	var target_y := (_crouch_camera_y if _is_crouching else _stand_camera_y)
	if _crouch_tween and _crouch_tween.is_valid():
		_crouch_tween.kill()
	_crouch_tween = create_tween()
	_crouch_tween.tween_property(_pivot, "position:y", target_y, crouch_transition_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _adjust_collider_height(crouch: bool):
	var cs: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		for c in get_children():
			var cs2 := c as CollisionShape3D
			if cs2:
				cs = cs2
				break
	if cs and cs.shape and cs.shape is CapsuleShape3D:
		var cap := cs.shape as CapsuleShape3D
		var full_height := cap.height + cap.radius * 2.0
		if _standing_capsule_height < 0.0:
			_standing_capsule_height = cap.height
			_standing_full_height = full_height
		if crouch:
			var target_full := _standing_full_height * crouch_height_scale
			cap.height = max(0.05, target_full - cap.radius * 2.0)
		else:
			cap.height = _standing_capsule_height
	elif cs and cs.shape and cs.shape is CylinderShape3D:
		var cyl := cs.shape as CylinderShape3D
		if _standing_cylinder_height < 0.0:
			_standing_cylinder_height = cyl.height
			_standing_full_height = cyl.height
		if crouch:
			cyl.height = _standing_cylinder_height * crouch_height_scale
		else:
			cyl.height = _standing_cylinder_height
	if crouch:
		global_position.y -= 0.05
	else:
		global_position.y += 0.05

# --- Human vision overlay helpers ---
func _ensure_human_vision_overlay(parent_layer: CanvasLayer) -> void:
	if not is_instance_valid(parent_layer):
		return
	if _vision_rect and is_instance_valid(_vision_rect):
		return
	# Create a full-screen ColorRect with the human vision shader
	var rect := ColorRect.new()
	rect.name = "HumanVisionOverlay"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(1,1,1,1)
	# Fill the screen
	rect.anchor_left = 0; rect.anchor_top = 0; rect.anchor_right = 1; rect.anchor_bottom = 1
	rect.offset_left = 0; rect.offset_top = 0; rect.offset_right = 0; rect.offset_bottom = 0
	# Material
	var sh := load("res://scenes/HumanVision.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	# Insert as first child so crosshair/UI draw above
	parent_layer.add_child(rect)
	parent_layer.move_child(rect, 0)
	_vision_rect = rect
	# Apply initial params and visibility
	_set_human_vision_visible(human_vision_enabled)
	_update_human_vision_uniforms()

func _set_human_vision_visible(vis: bool) -> void:
	if _vision_rect and is_instance_valid(_vision_rect):
		_vision_rect.visible = vis

func _update_human_vision_uniforms() -> void:
	if not (_vision_rect and is_instance_valid(_vision_rect)):
		return
	var sm := _vision_rect.material as ShaderMaterial
	if sm == null:
		return
	sm.set_shader_parameter("vignette_strength", clamp(vision_vignette_strength, 0.0, 2.0))
	sm.set_shader_parameter("vignette_softness", clamp(vision_vignette_softness, 0.0, 1.0))
	sm.set_shader_parameter("distortion_amount", clamp(vision_distortion, -0.5, 0.5))
	sm.set_shader_parameter("chroma_amount", clamp(vision_chromatic, 0.0, 4.0))
	sm.set_shader_parameter("grain_amount", clamp(vision_grain, 0.0, 1.0))

# Public API to control from menus if needed
func set_human_vision_enabled(flag: bool) -> void:
	human_vision_enabled = flag
	_set_human_vision_visible(flag)

func set_human_vision_vignette(strength: float, softness: float) -> void:
	vision_vignette_strength = strength
	vision_vignette_softness = softness
	_update_human_vision_uniforms()

func set_human_vision_distortion(amount: float) -> void:
	vision_distortion = amount
	_update_human_vision_uniforms()

func set_human_vision_chromatic(amount: float) -> void:
	vision_chromatic = amount
	_update_human_vision_uniforms()

func set_human_vision_grain(amount: float) -> void:
	vision_grain = amount
	_update_human_vision_uniforms()

# Attempt to nudge up small steps when a low obstacle is in front but there is clearance at knee height
func _apply_step_assist(_delta: float) -> void:
	# Respect global toggle
	if not step_assist_enabled:
		return
	# If area-gated, only enable when inside one or more StepAssistArea volumes
	if step_assist_requires_area and _step_assist_area_count <= 0:
		return
	if not is_on_floor():
		return
	# Require forward intent
	var planar := Vector2(_vel.x, _vel.z)
	if planar.length() < 0.1:
		return
	var forward := Vector3(planar.x, 0.0, planar.y).normalized()
	var space := get_world_3d().direct_space_state
	# Low ray (foot level) detects a small obstacle immediately ahead
	var from_low := global_transform.origin + Vector3(0.0, 0.1, 0.0)
	var to_low := from_low + forward * step_check_forward_distance
	var ql := PhysicsRayQueryParameters3D.create(from_low, to_low)
	ql.collide_with_areas = false
	ql.collide_with_bodies = true
	ql.exclude = [get_rid()]
	var hit_low := space.intersect_ray(ql)
	if hit_low.is_empty():
		return
	# High ray (knee height) should be clear to allow stepping up
	var knee: float = clampf(step_max_height, 0.1, 1.0)
	var from_high := global_transform.origin + Vector3(0.0, knee, 0.0)
	var to_high := from_high + forward * step_check_forward_distance
	var qh := PhysicsRayQueryParameters3D.create(from_high, to_high)
	qh.collide_with_areas = false
	qh.collide_with_bodies = true
	qh.exclude = [get_rid()]
	var hit_high := space.intersect_ray(qh)
	if not hit_high.is_empty():
		return
	# Nudge upward to climb the step
	_vel.y = max(_vel.y, step_up_boost)
