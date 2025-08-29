extends Area3D

@onready var anim: AnimationPlayer = $"../AnimationPlayer"

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		if not anim.is_playing():
			anim.play("toggle-on")

func _on_body_exited(body: Node):
	if body.is_in_group("player"):
		if not anim.is_playing():
			anim.play("toggle-off")
