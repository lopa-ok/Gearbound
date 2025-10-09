# filepath: /Users/lopa/test/scenes/scripts/interactables/CreditsTrigger.gd
extends Area3D

@export var glow_color: Color = Color(1, 1, 1)
@export var glow_strength: float = 2.0
@export var show_on_body_entered: bool = true
@export var credits_menu_path: NodePath
@export var arm_delay_sec: float = 0.5
# New: load a scene directly when touched
@export var load_scene_on_touch: bool = true
@export var credits_scene_path: String = "res://scenes/CreditsScene.tscn"

var _armed: bool = false
var _initial_bodies: = {}

func _ready() -> void:
	# Optional: add a basic glowing material if a MeshInstance3D child exists
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh and mesh.mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0, 0, 0, 1)
		mat.emission_enabled = true
		mat.emission = glow_color
		mat.emission_energy_multiplier = glow_strength
		mesh.set_surface_override_material(0, mat)
	# Connect signals
	body_entered.connect(_on_body_entered)
	print("[CreditsTrigger] Ready | scene_path=%s menu_path=%s" % [credits_scene_path, credits_menu_path])
	# Arm after a short delay to avoid triggering on initial spawn overlap
	_call_deferred_arm()

func _call_deferred_arm() -> void:
	await get_tree().create_timer(max(arm_delay_sec, 0.0)).timeout
	# Record any bodies currently overlapping to ignore their first enter event
	_initial_bodies = {}
	for b in get_overlapping_bodies():
		_initial_bodies[b.get_instance_id()] = true
	_armed = true

func _on_body_entered(body: Node) -> void:
	if not show_on_body_entered:
		return
	if not _armed:
		return
	var id := body.get_instance_id()
	if _initial_bodies.has(id):
		# Ignore initial overlap; clear so future re-entries will work
		_initial_bodies.erase(id)
		return
	# Immediately black out the screen
	if Engine.has_singleton("Transition"):
		Transition.cut_to_black()
	# Prefer loading a standalone scene if enabled
	if load_scene_on_touch and credits_scene_path != "":
		get_tree().change_scene_to_file(credits_scene_path)
		return
	# Fallback: open a menu node if provided
	var menu := get_node_or_null(credits_menu_path)
	if menu and menu.has_method("open"):
		menu.open()
	else:
		push_warning("[CreditsTrigger] No scene path set and credits menu not found or missing 'open': %s" % credits_menu_path)
