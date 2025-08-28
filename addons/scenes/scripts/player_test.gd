extends VehicleBody3D


const MAX_STEER = 0.8
const ENGINE_POWER = 310



func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)



func _process(delta):
	steering = move_toward(steering, Input.get_axis("ui_right","ui_left") * MAX_STEER, delta * 2.5)
	engine_force = Input.get_axis("ui_down","ui_up") * ENGINE_POWER
