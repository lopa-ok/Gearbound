extends Area3D

@onready var interact_icon: Label3D = $"../Label3D"

func _ready():
	interact_icon.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node):
	print("Entered:", body.name)
	print("Is in player group:", body.is_in_group("player"))
	if body.is_in_group("player"):
		print("Setting icon visible to TRUE")
		interact_icon.visible = true
		print("Icon visible state:", interact_icon.visible)

func _on_body_exited(body: Node):
	print("Exited:", body.name)
	print("Is in player group:", body.is_in_group("player"))
	if body.is_in_group("player"):
		print("Setting icon visible to FALSE")
		interact_icon.visible = false
		print("Icon visible state:", interact_icon.visible)
