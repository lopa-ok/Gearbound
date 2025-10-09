extends RigidBody3D

# Basic pushable physics object.
# Attach to a RigidBody3D with a CollisionShape3D (and optional MeshInstance3D) to make it pushable.
# Designed to be interactable by players, the car, and general world forces.
# Configure mass, friction and damping in the Inspector. This script layers on:
# - Awake on nearby player/car movement (optional sleep optimization)
# - Ground stick / anti jitter small downward force
# - Velocity capping (linear & angular) to prevent wild launches
# - Optional impulse assist when the player walks into it (helps lighter players move heavier objects)
# - Simple SFX hooks for start/stop sliding and impacts
# - Network friendliness: authority-safe impulses if in multiplayer later (placeholder)

@export var assist_push: bool = true
@export var assist_push_force: float = 6.0
@export var assist_max_speed: float = 4.0
@export var linear_speed_limit: float = 18.0
@export var angular_speed_limit: float = 18.0
@export var ground_stick_force: float = 2.5
@export var wake_distance: float = 6.0
@export var sleep_when_far: bool = false
@export var impact_sound_min_speed: float = 2.0
@export var slide_sound_min_speed: float = 0.2
@export var slide_sound_stop_speed: float = 0.1
@export var slide_sound_interval: float = 0.35
@export var impact_cooldown: float = 0.25
@export var friction_multiplier: float = 1.0 # Can be used to quickly tune PhysicsMaterial friction externally.

# Optional nodes (drag in if you have them)
@export var slide_audio: AudioStreamPlayer3D
@export var impact_audio: AudioStreamPlayer3D

var _last_slide_time: float = 0.0
var _last_impact_time: float = 0.0
var _base_friction: float = 1.0

func _ready():
	# Cache base friction if a PhysicsMaterial override exists (Godot 4: shapes don't store friction directly)
	if physics_material_override:
		_base_friction = physics_material_override.friction
	# Ensure continuous collision if fast (optional):
	continuous_cd = true
	# Enable contact monitoring so impact callback always fires and body blocks CharacterBody properly.
	contact_monitor = true
	if max_contacts_reported < 8:
		max_contacts_reported = 8

func _physics_process(delta: float) -> void:
	if sleep_when_far:
		_update_sleep_state()
	_apply_ground_stick(delta)
	_apply_speed_limits()
	_handle_slide_sfx()

func _update_sleep_state():
	# Put object to sleep if no players/cars are near. (Assumes players are in group "players" and car maybe in group "car").
	var near := false
	for node in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(node) and global_position.distance_to(node.global_position) <= wake_distance:
			near = true
			break
	if not near:
		for c in get_tree().get_nodes_in_group("car"):
			if global_position.distance_to(c.global_position) <= wake_distance:
				near = true
				break
	if near and sleeping:
		sleeping = false
	elif (not near) and (not sleeping):
		sleeping = true

func _apply_ground_stick(_delta: float):
	# Light downward force to reduce jitter when resting on uneven ground.
	if linear_velocity.length() < 0.25:
		apply_central_force(Vector3.DOWN * ground_stick_force)

func _apply_speed_limits():
	if linear_velocity.length() > linear_speed_limit:
		linear_velocity = linear_velocity.normalized() * linear_speed_limit
	if angular_velocity.length() > angular_speed_limit:
		angular_velocity = angular_velocity.normalized() * angular_speed_limit

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if assist_push:
		_assist_push(state)

func _assist_push(_state: PhysicsDirectBodyState3D):
	# Provide a gentle extra impulse in direction of player push when their body velocity intersects us.
	# This assumes player bodies are CharacterBody3D or RigidBody3D in group "players".
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p):
			continue
		var to_obj = global_position - p.global_position
		if to_obj.length() > 2.1:
			continue
		# Determine player horizontal velocity
		var player_vel: Vector3 = Vector3.ZERO
		if p.has_method("get_velocity"):
			player_vel = p.get_velocity()
		elif "velocity" in p and p.velocity is Vector3:
			player_vel = p.velocity
		elif "linear_velocity" in p and p.linear_velocity is Vector3:
			player_vel = p.linear_velocity
		player_vel.y = 0
		if player_vel.length() < 0.1:
			continue
		# Check if player moving toward object
		var dir = player_vel.normalized()
		var toward = dir.dot(to_obj.normalized()) < -0.2 # Player moving roughly toward object
		if toward and linear_velocity.length() < assist_max_speed:
			apply_central_force(dir * assist_push_force)

# Basic collision callback for impact SFX
func _on_body_entered(_body: Node) -> void:
	var speed = linear_velocity.length()
	var now = Time.get_ticks_msec() / 1000.0
	if speed >= impact_sound_min_speed and impact_audio and (now - _last_impact_time) > impact_cooldown:
		impact_audio.play()
		_last_impact_time = now

func _handle_slide_sfx():
	if not slide_audio:
		return
	var horiz_speed = Vector3(linear_velocity.x, 0, linear_velocity.z).length()
	var now = Time.get_ticks_msec() / 1000.0
	if horiz_speed >= slide_sound_min_speed:
		if not slide_audio.playing and (now - _last_slide_time) > slide_sound_interval:
			slide_audio.play()
			_last_slide_time = now
	elif horiz_speed <= slide_sound_stop_speed and slide_audio.playing:
		slide_audio.stop()

# Optional helper to dynamically scale friction (e.g. for ice or mud). Call externally.
func set_friction_scale(mult: float):
	friction_multiplier = mult
	if physics_material_override:
		physics_material_override.friction = _base_friction * friction_multiplier

# (Optional) Call to apply an external shove
func shove(direction: Vector3, impulse_strength: float):
	if direction.length() == 0:
		return
	apply_impulse(direction.normalized() * impulse_strength)

# Signals: connect the RigidBody3D's body_entered to _on_body_entered for impact SFX.
