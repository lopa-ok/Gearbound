extends Node3D

@onready var screen_mesh: MeshInstance3D = $MeshInstance3D
@onready var video_player: VideoStreamPlayer = $SubViewport/VideoStreamPlayer

var screen_material: ShaderMaterial
var target_alpha: float = 0.0

enum FitMode { STRETCH, LETTERBOX, COVER }
@export var fit_mode: FitMode = FitMode.LETTERBOX
@export var letterbox_color: Color = Color(0,0,0,1)
# New: auto-fit update when video dimensions or mesh changes
@export var auto_fit_update: bool = true
@export var fit_poll_interval: float = 0.3
var _fit_t: float = 0.0
var _last_video_wh: Vector2i = Vector2i.ZERO
var _last_quad_size: Vector2 = Vector2.ZERO

# --- Reveal animation settings ---
@export var reveal_on_fade_in: bool = true
enum RevealAxis { WIDTH, HEIGHT }
@export var reveal_axis: RevealAxis = RevealAxis.HEIGHT
@export var reveal_duration: float = 0.6
@export var reveal_softness: float = 0.0
@export var reveal_on_fade_out: bool = true
var _reveal_anim: Tween

func _ready():
	# setup video and material
	video_player.autoplay = true
	video_player.loop = true
	if not video_player.is_playing():
		video_player.play()
	var sh := load("res://scenes/FloatingScreen.gdshader")
	screen_material = ShaderMaterial.new()
	screen_material.shader = sh
	screen_material.set_shader_parameter("screen_tex", video_player.get_video_texture())
	screen_material.set_shader_parameter("screen_alpha", 0.0)
	screen_material.set_shader_parameter("reveal_amount", 1.0)
	screen_material.set_shader_parameter("reveal_axis_vertical", reveal_axis == RevealAxis.HEIGHT)
	screen_material.set_shader_parameter("reveal_softness", reveal_softness)
	_update_fit_params()
	# Safe material assignment: use surface override only if a surface exists, else fallback
	if screen_mesh and screen_mesh.mesh and screen_mesh.mesh.get_surface_count() > 0:
		screen_mesh.set_surface_override_material(0, screen_material)
	else:
		screen_mesh.material_override = screen_material
	visible = false
	set_process(auto_fit_update)

func _process(delta: float) -> void:
	if not auto_fit_update:
		return
	_fit_t -= delta
	if _fit_t > 0.0:
		return
	_fit_t = max(0.05, fit_poll_interval)
	var tex: Texture2D = video_player.get_video_texture()
	var cur_wh := Vector2i(0,0)
	if tex:
		cur_wh = Vector2i(tex.get_width(), tex.get_height())
	var cur_quad := Vector2.ZERO
	if screen_mesh and screen_mesh.mesh and screen_mesh.mesh is QuadMesh:
		cur_quad = (screen_mesh.mesh as QuadMesh).size
	if cur_wh != _last_video_wh or cur_quad != _last_quad_size:
		_last_video_wh = cur_wh
		_last_quad_size = cur_quad
		_update_fit_params()

func fade_in(duration: float = 0.2):
	visible = true
	_update_fit_params()
	# Replay reveal every time
	if reveal_on_fade_in:
		start_reveal(reveal_axis, reveal_duration)
	target_alpha = 1.0
	var tween = create_tween()
	tween.tween_method(_set_alpha, float(screen_material.get_shader_parameter("screen_alpha")), target_alpha, duration)

func fade_out(duration: float = 0.2):
	if reveal_on_fade_out:
		# Collapse into a line first (keep alpha while collapsing), then fade out and hide
		visible = true
		_update_fit_params()
		_set_alpha(1.0)
		start_reveal_reverse(reveal_axis, reveal_duration)
		if _reveal_anim and _reveal_anim.is_valid():
			_reveal_anim.finished.connect(func():
				target_alpha = 0.0
				var atw = create_tween()
				atw.tween_method(_set_alpha, float(screen_material.get_shader_parameter("screen_alpha")), target_alpha, duration)
				atw.finished.connect(_on_fade_finished))
	else:
		target_alpha = 0.0
		var tween = create_tween()
		tween.tween_method(_set_alpha, float(screen_material.get_shader_parameter("screen_alpha")), target_alpha, duration)
		tween.finished.connect(_on_fade_finished)

func _set_alpha(a: float) -> void:
	if screen_material:
		screen_material.set_shader_parameter("screen_alpha", clamp(a, 0.0, 1.0))

func _on_fade_finished():
	if target_alpha <= 0.0:
		visible = false

func set_fit_mode(mode: FitMode) -> void:
	fit_mode = mode
	_update_fit_params()

func set_letterbox_color(col: Color) -> void:
	letterbox_color = col
	if screen_material:
		screen_material.set_shader_parameter("bar_color", col)

func _update_fit_params() -> void:
	if not screen_material:
		return
	var tex: Texture2D = video_player.get_video_texture()
	var video_aspect := 16.0/9.0
	if tex:
		var w := float(tex.get_width())
		var h := float(tex.get_height())
		if w > 0.0 and h > 0.0:
			video_aspect = w / h
	var mesh_aspect := 1.0
	var size := Vector2(1, 1)
	if screen_mesh and screen_mesh.mesh and screen_mesh.mesh is QuadMesh:
		size = (screen_mesh.mesh as QuadMesh).size
	var gbasis := screen_mesh.global_transform.basis
	var sx := gbasis.x.length()
	var sy := gbasis.y.length()
	if sy != 0.0:
		mesh_aspect = (size.x * sx) / (size.y * sy)
	else:
		mesh_aspect = 1.0
	var uv_scale := Vector2(1,1)
	if fit_mode == FitMode.STRETCH:
		uv_scale = Vector2(1,1)
	elif fit_mode == FitMode.LETTERBOX:
		if video_aspect > mesh_aspect:
			uv_scale = Vector2(1, mesh_aspect / video_aspect)
		else:
			uv_scale = Vector2(video_aspect / mesh_aspect, 1)
	elif fit_mode == FitMode.COVER:
		if video_aspect > mesh_aspect:
			uv_scale = Vector2(mesh_aspect / video_aspect, 1)
		else:
			uv_scale = Vector2(1, video_aspect / mesh_aspect)
	screen_material.set_shader_parameter("uv_scale", uv_scale)
	screen_material.set_shader_parameter("bar_color", letterbox_color)

# Reveal animation using shader mask
func start_reveal(axis: RevealAxis = RevealAxis.HEIGHT, duration: float = -1.0) -> void:
	if not is_instance_valid(screen_material):
		return
	if _reveal_anim and _reveal_anim.is_valid():
		_reveal_anim.kill()
	reveal_axis = axis
	if duration > 0.0:
		reveal_duration = duration
	screen_material.set_shader_parameter("reveal_axis_vertical", reveal_axis == RevealAxis.HEIGHT)
	screen_material.set_shader_parameter("reveal_softness", reveal_softness)
	screen_material.set_shader_parameter("reveal_amount", 0.0)
	_reveal_anim = create_tween()
	_reveal_anim.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reveal_anim.tween_method(_set_reveal_amount, 0.0, 1.0, reveal_duration)

func start_reveal_reverse(axis: RevealAxis = RevealAxis.HEIGHT, duration: float = -1.0) -> void:
	if not is_instance_valid(screen_material):
		return
	if _reveal_anim and _reveal_anim.is_valid():
		_reveal_anim.kill()
	reveal_axis = axis
	if duration > 0.0:
		reveal_duration = duration
	screen_material.set_shader_parameter("reveal_axis_vertical", reveal_axis == RevealAxis.HEIGHT)
	screen_material.set_shader_parameter("reveal_softness", reveal_softness)
	var current := float(screen_material.get_shader_parameter("reveal_amount"))
	_reveal_anim = create_tween()
	_reveal_anim.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_reveal_anim.tween_method(_set_reveal_amount, current, 0.0, reveal_duration)

func _set_reveal_amount(v: float) -> void:
	if screen_material:
		screen_material.set_shader_parameter("reveal_amount", clamp(v, 0.0, 1.0))
