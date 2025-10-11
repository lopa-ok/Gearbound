extends Control

@export var labels: PackedStringArray = ["GAME TITLE", "Play", "Options", "Quit"]
@export var center_in_view: bool = true
@export var horizontal_alignment: int = HORIZONTAL_ALIGNMENT_CENTER
@export var vertical_alignment: int = VERTICAL_ALIGNMENT_CENTER
@export var label_spacing: int = 12
@export var label_margin: int = 24
@export var title_scale: float = 1.3

@onready var box: VBoxContainer = $Center/Margin/Box if has_node("Center/Margin/Box") else null

func _ready() -> void:
	if box == null:
		return
	# Remove any existing labels
	for c in box.get_children():
		c.queue_free()
	box.add_theme_constant_override("separation", label_spacing)
	for i in range(labels.size()):
		var l := Label.new()
		l.text = labels[i]
		# Assign enum values directly (no constructors)
		l.horizontal_alignment = horizontal_alignment
		l.vertical_alignment = vertical_alignment
		if i == 0 and title_scale != 1.0:
			l.scale = Vector2(title_scale, title_scale)
		box.add_child(l)
	# Centering via containers; no background used
	$Center.visible = center_in_view

func set_labels(new_labels: PackedStringArray) -> void:
	labels = new_labels
	_ready()
