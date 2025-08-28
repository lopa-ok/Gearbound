extends OmniLight3D  # or SpotLight3D / DirectionalLight3D depending on your node

@export var target: NodePath  # drag your Player or object here in the inspector
@export var min_intensity: float = 0.4
@export var max_intensity: float = 1.0
@export var max_distance: float = 15.0  # distance at which light is weakest

var player: Node3D

func _ready():
	if target != NodePath():
		player = get_node(target)

func _process(delta):
	if player:
		var dist = global_position.distance_to(player.global_position)

		# map distance → intensity
		var intensity = lerp(max_intensity, min_intensity, clamp(dist / max_distance, 0.0, 1.0))

		light_energy = intensity
