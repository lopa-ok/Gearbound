extends VehicleBody3D

const MAX_STEER = 0.8
const ENGINE_POWER = 400

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D
@onready var ray: RayCast3D = $CameraPivot/RayCast3D

# Original camera offset & angle (your values)
var camera_offset := Vector3(0, 3.331, -5.679)
var camera_rotation := Vector3(-3.1, 180, 0)

func _ready():
	camera_3d.rotation_degrees = camera_rotation

func _process(delta):
	# Car controls
	steering = move_toward(steering, Input.get_axis("ui_right", "ui_left") * MAX_STEER, delta * 2.5)
	engine_force = Input.get_axis("ui_down", "ui_up") * ENGINE_POWER

	# Camera pivot follows car
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
