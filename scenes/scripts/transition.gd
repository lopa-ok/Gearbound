extends CanvasLayer

@onready var rect: ColorRect = $ColorRect
@onready var anim: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	# Start hidden, safe progress
	rect.visible = false
	_set_shader_progress(0.0)

func _set_shader_progress(v: float) -> void:
	var mat = rect.material
	if mat and mat is ShaderMaterial:
		mat.set_shader_parameter("progress", v)

func play_transition(anim_name: String) -> void:
	# Corrected logic:
	if anim_name == "transition_out":
		# Screen should cover → start from 0
		_set_shader_progress(0.0)
	elif anim_name == "transition_in":
		# Screen should already be covered → start from 1
		_set_shader_progress(1.0)

	rect.visible = true
	anim.play(anim_name)
	await anim.animation_finished
	rect.visible = false
