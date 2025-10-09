extends Area3D
## StepAssistArea: When the human enters this area, their step assist is enabled (if gated).
## Place this around zones where you want small-step auto-climb to be active.

@export var only_human_group: StringName = "human_player"

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if not body or not is_instance_valid(body):
		return
	if only_human_group != StringName("") and not body.is_in_group(only_human_group):
		return
	if body.has_method("step_assist_area_enter"):
		body.step_assist_area_enter()

func _on_body_exited(body: Node) -> void:
	if not body or not is_instance_valid(body):
		return
	if only_human_group != StringName("") and not body.is_in_group(only_human_group):
		return
	if body.has_method("step_assist_area_exit"):
		body.step_assist_area_exit()
