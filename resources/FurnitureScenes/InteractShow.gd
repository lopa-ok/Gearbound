extends Area3D

const SETTINGS_MENU = preload("res://scenes/SettingsMenu.tscn")

@onready var interact_icon: Label3D = $"../Label3D"
var settings_menu: Control
var player_inside := false

func _ready():
	interact_icon.visible = false

	# instance settings menu
	settings_menu = SETTINGS_MENU.instantiate()
	settings_menu.visible = false
	call_deferred("add_child", settings_menu)  # safe way to add it

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	if player_inside and Input.is_action_just_pressed("interact"):
		settings_menu.visible = true
	
	if settings_menu.visible and Input.is_action_just_pressed("ui_cancel"): # usually Esc
		settings_menu.visible = false

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		player_inside = true
		interact_icon.visible = true

func _on_body_exited(body: Node):
	if body.is_in_group("player"):
		player_inside = false
		interact_icon.visible = false
