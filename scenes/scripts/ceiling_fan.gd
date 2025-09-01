extends Node3D  # attach to the fan model root

@export var rotation_speed: float = 180.0 # degrees per second

func _process(delta):
	# Rotate around the Y-axis
	rotate_y(deg_to_rad(rotation_speed * delta))
