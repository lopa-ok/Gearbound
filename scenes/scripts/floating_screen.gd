extends Node3D

@onready var screen_mesh: MeshInstance3D = $MeshInstance3D
@onready var subviewport: SubViewport = $SubViewport
@onready var video_player: VideoStreamPlayer = $SubViewport/VideoStreamPlayer

var screen_material: StandardMaterial3D  # reference to the material
var target_alpha: float = 0.0

func _ready():
	# Play video automatically and loop
	video_player.autoplay = true
	video_player.loop = true
	if not video_player.is_playing():
		video_player.play()

	# Create a material and assign it to the screen mesh
	screen_material = StandardMaterial3D.new()
	screen_material.albedo_texture = subviewport.get_texture()
	screen_material.roughness = 1.0
	screen_material.metallic = 0.0
	screen_material.flags_unshaded = true
	screen_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	screen_material.albedo_color.a = 0.0  # start invisible

	screen_mesh.set_surface_override_material(0, screen_material)
	visible = false

# Fade in over `duration` seconds
func fade_in(duration: float = 0.2):
	visible = true
	target_alpha = 1.0
	var tween = create_tween()
	tween.tween_property(screen_material, "albedo_color:a", target_alpha, duration)

# Fade out over `duration` seconds
func fade_out(duration: float = 0.2):
	target_alpha = 0.0
	var tween = create_tween()
	tween.tween_property(screen_material, "albedo_color:a", target_alpha, duration)
	tween.finished.connect(Callable(self, "_on_fade_finished"))

func _on_fade_finished():
	if target_alpha <= 0.0:
		visible = false
