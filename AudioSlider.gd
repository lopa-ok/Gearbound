extends HSlider
# If vertical, swap HSlider → VSlider in the scene

@export var bus_name: String
var bus_index: int

# Grabber textures
const GRABBER_NORMAL  := preload("res://resources/Textures/grabber_rect_48x24.png")
const GRABBER_HOVER   := preload("res://resources/Textures/grabber_rect_48x24_hover.png")
const GRABBER_PRESSED := preload("res://resources/Textures/grabber_rect_48x24_pressed.png")

func _ready() -> void:
	# Setup audio link
	bus_index = AudioServer.get_bus_index(bus_name)
	value_changed.connect(_on_value_changed)
	value = db_to_linear(AudioServer.get_bus_volume_db(bus_index))

	# Apply grabber icons after ready
	call_deferred("_apply_custom_theme")

func _apply_custom_theme() -> void:
	var t := Theme.new()

	# Apply grabber icons for both HSlider and Slider base class
	for cls in [&"HSlider", &"Slider", &"VSlider"]:
		t.set_icon(&"grabber", cls, GRABBER_NORMAL)
		t.set_icon(&"grabber_highlight", cls, GRABBER_HOVER)
		t.set_icon(&"grabber_pressed", cls, GRABBER_PRESSED)

	self.theme = t

	# Force overrides directly too
	add_theme_icon_override("grabber", GRABBER_NORMAL)
	add_theme_icon_override("grabber_highlight", GRABBER_HOVER)
	add_theme_icon_override("grabber_pressed", GRABBER_PRESSED)

func _on_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))
