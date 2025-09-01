extends Area3D

const FLOATING_SCREEN = preload("res://scenes/FloatingScreen.tscn")

@onready var anim: AnimationPlayer = $"../AnimationPlayer"
var floating_screen_instance: Node3D = null

# How high above the button the screen should float
@export var screen_height: float = 3.0
# Scale of the screen
@export var screen_scale: Vector3 = Vector3(4, 2, 1)
# Fade duration
@export var fade_duration: float = 0.2

func _ready():
	# Instance the floating screen
	floating_screen_instance = FLOATING_SCREEN.instantiate()
	call_deferred("_add_screen_deferred")

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _add_screen_deferred():
	get_tree().current_scene.add_child(floating_screen_instance)
	if is_inside_tree():
		floating_screen_instance.global_transform.origin = global_transform.origin + Vector3(0, screen_height, 0)
	floating_screen_instance.scale = screen_scale
	floating_screen_instance.visible = false

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		if not anim.is_playing():
			anim.play("toggle-on")
		if floating_screen_instance:
			floating_screen_instance.fade_in(fade_duration)

func _on_body_exited(body: Node):
	if body.is_in_group("player"):
		if not anim.is_playing():
			anim.play("toggle-off")
		if floating_screen_instance:
			floating_screen_instance.fade_out(fade_duration)
