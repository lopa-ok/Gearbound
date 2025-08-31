extends VehicleBody3D

const MAX_STEER = 0.8
const ENGINE_POWER = 400

# Engine sound settings
const BASE_PITCH := 0.8
const MAX_PITCH := 2.2
const THROTTLE_VOLUME := -8.0
const ROLLING_VOLUME := -15.0
const MIN_SPEED_FOR_SOUND := 1.0
const MIN_SPINDOWN_TIME := 1.0   # Minimum spindown time
const MAX_SPINDOWN_TIME := 6.0   # Maximum spindown time
const THROTTLE_TIME_FOR_MAX_SPINDOWN := 3.0  # Throttle duration needed for max spindown

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D
@onready var ray: RayCast3D = $CameraPivot/RayCast3D
@onready var engine_sound: AudioStreamPlayer = $EngineSound

# Audio state variables
var current_audio_state := ""
var target_pitch := BASE_PITCH
var target_volume := ROLLING_VOLUME
var engine_smoothing := 3.0
var should_play_audio := false
var engine_momentum := 0.0  # Simulates engine spinning down
var throttle_start_time := 0.0
var throttle_duration := 0.0
var is_throttling := false

# Original camera offset & angle
var camera_offset := Vector3(0, 3.331, -5.679)
var camera_rotation := Vector3(-3.1, 180, 0)

func _ready():
	camera_3d.rotation_degrees = camera_rotation
	# Initialize engine sound but don't play yet
	engine_sound.pitch_scale = BASE_PITCH
	engine_sound.volume_db = ROLLING_VOLUME

func _process(delta):
	# --- CAR CONTROLS ---
	steering = move_toward(steering, Input.get_axis("ui_right", "ui_left") * MAX_STEER, delta * 2.5)
	engine_force = Input.get_axis("ui_down", "ui_up") * ENGINE_POWER
	
	# --- CAMERA FOLLOW ---
	camera_pivot.global_position = camera_pivot.global_position.lerp(global_position, delta * 20.0)
	camera_pivot.transform = camera_pivot.transform.interpolate_with(transform, delta * 5.0)
	
	# Camera collision check
	ray.target_position = camera_offset
	var desired_pos = camera_offset
	if ray.is_colliding():
		var hit_pos = ray.get_collision_point()
		var pivot_pos = camera_pivot.global_position
		var dir = camera_offset.normalized()
		var dist = pivot_pos.distance_to(hit_pos) - 0.3
		desired_pos = dir * dist
	
	# Smooth camera movement
	camera_3d.position = camera_3d.position.lerp(desired_pos, delta * 10.0)
	
	# --- IMPROVED ENGINE SOUND ---
	update_engine_audio(delta)

func update_engine_audio(delta):
	var throttle_input = Input.get_axis("ui_down", "ui_up")
	var speed = linear_velocity.length()
	var abs_throttle = abs(throttle_input)
	var current_unix_time = Time.get_time_dict_from_system().get("unix", 0)
	
	# Track throttle duration
	if abs_throttle > 0.05:
		if not is_throttling:
			# Just started throttling
			throttle_start_time = current_unix_time
			is_throttling = true
		throttle_duration = current_unix_time - throttle_start_time
		engine_momentum = 1.0  # Full engine momentum when throttling
	else:
		if is_throttling:
			# Just released throttle - calculate spindown time based on how long we were throttling
			var spindown_factor = min(throttle_duration / THROTTLE_TIME_FOR_MAX_SPINDOWN, 1.0)
			var calculated_spindown_time = MIN_SPINDOWN_TIME + (spindown_factor * (MAX_SPINDOWN_TIME - MIN_SPINDOWN_TIME))
			is_throttling = false
		
		# Gradually reduce engine momentum based on calculated spindown time
		if engine_momentum > 0.0:
			var current_spindown_time = MIN_SPINDOWN_TIME + (min(throttle_duration / THROTTLE_TIME_FOR_MAX_SPINDOWN, 1.0) * (MAX_SPINDOWN_TIME - MIN_SPINDOWN_TIME))
			engine_momentum = max(0.0, engine_momentum - (delta / current_spindown_time))
	
	var new_audio_state = ""
	should_play_audio = false
	
	# Determine audio state
	if abs_throttle > 0.05:
		# Active throttle - full power sound
		new_audio_state = "throttle"
		should_play_audio = true
		var throttle_factor = abs_throttle * 0.7
		var speed_factor = min(speed / 40.0, 1.0) * 0.3
		target_pitch = BASE_PITCH + (throttle_factor + speed_factor) * (MAX_PITCH - BASE_PITCH)
		target_volume = THROTTLE_VOLUME
		engine_smoothing = 8.0  # Very responsive when throttling
		
	elif engine_momentum > 0.0:
		# Engine spinning down after throttle release
		new_audio_state = "spindown"
		should_play_audio = true
		# Pitch and volume based on remaining momentum
		var momentum_factor = engine_momentum * 0.6
		var speed_factor = min(speed / 30.0, 1.0) * 0.2
		target_pitch = BASE_PITCH + (momentum_factor + speed_factor) * (MAX_PITCH - BASE_PITCH)
		# Volume fades smoothly based on momentum, reaching very quiet but not silent
		var min_volume = -30.0  # Don't go completely silent during spindown
		target_volume = lerp(THROTTLE_VOLUME, min_volume, 1.0 - engine_momentum)
		engine_smoothing = 2.0  # Smooth spindown
		
	else:
		# Complete silence
		new_audio_state = "silent"
		should_play_audio = false
		engine_smoothing = 3.0
	
	# Handle audio playback
	if should_play_audio:
		if not engine_sound.playing:
			engine_sound.play()
		# Smooth audio parameter changes
		engine_sound.pitch_scale = lerp(engine_sound.pitch_scale, target_pitch, delta * engine_smoothing)
		engine_sound.volume_db = lerp(engine_sound.volume_db, target_volume, delta * engine_smoothing)
	else:
		# Final gentle fade when momentum is completely gone
		if engine_sound.playing:
			engine_sound.volume_db = lerp(engine_sound.volume_db, -50.0, delta * 1.0)
			if engine_sound.volume_db < -45.0:
				engine_sound.stop()
	
	current_audio_state = new_audio_state
