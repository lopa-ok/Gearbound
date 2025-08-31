extends VehicleBody3D

@export var engine_power: float = 200.0     # base speed
@export var steer_amount: float = 0.6       # base steering angle
@export var wobble_strength: float = 0.05   # how much it wiggles
@export var wobble_speed: float = 2.0       # how fast it wiggles

var time_passed: float = 0.0

func _physics_process(delta: float) -> void:
	time_passed += delta

	# Small steering variation (wobble)
	var steer_wobble = sin(time_passed * wobble_speed) * wobble_strength

	# Small engine variation (speed up/slow down slightly)
	var engine_wobble = cos(time_passed * wobble_speed * 0.7) * (engine_power * 0.05)

	steering = steer_amount + steer_wobble
	engine_force = engine_power + engine_wobble
	brake = 0.0
