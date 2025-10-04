extends Control

signal closed

@onready var crt_checkbox: CheckBox = %CRTToggle
@onready var crt_intensity: HSlider = %CRTIntensitySlider
@onready var crt_noise: HSlider = %CRTNoiseSlider
@onready var crt_flicker: HSlider = %CRTFlickerSlider

func _ready():
	# start hidden
	hide()
	# Style CRT sliders to match Audio sliders
	_call_style_sliders_deferred()
	# Initialize toggle from project settings (default true)
	var enabled := true
	if ProjectSettings.has_setting("game/video/crt_overlay_enabled"):
		enabled = bool(ProjectSettings.get_setting("game/video/crt_overlay_enabled"))
	crt_checkbox.button_pressed = enabled
	_apply_crt(enabled)
	# Initialize intensity from settings (default 1.0)
	var intensity := 1.0
	if ProjectSettings.has_setting("game/video/crt_effect_strength"):
		intensity = float(ProjectSettings.get_setting("game/video/crt_effect_strength"))
	crt_intensity.value = clamp(intensity, 0.0, 1.0)
	_apply_crt_intensity(crt_intensity.value)
	# Initialize noise & flicker (defaults match car exports)
	var noise := 0.008
	if ProjectSettings.has_setting("game/video/crt_noise_amount"):
		noise = float(ProjectSettings.get_setting("game/video/crt_noise_amount"))
	crt_noise.value = clamp(noise, 0.0, 1.0)
	_apply_crt_noise(crt_noise.value)
	var flicker := 0.02
	if ProjectSettings.has_setting("game/video/crt_flicker_amount"):
		flicker = float(ProjectSettings.get_setting("game/video/crt_flicker_amount"))
	crt_flicker.value = clamp(flicker, 0.0, 1.0)
	_apply_crt_flicker(crt_flicker.value)

func grab_default_focus() -> void:
	var back := get_node_or_null("%Back") as BaseButton
	if back:
		back.grab_focus()

func _on_back_pressed() -> void:
	hide()
	emit_signal("closed")

func _on_crt_toggled(pressed: bool) -> void:
	_apply_crt(pressed)
	ProjectSettings.set_setting("game/video/crt_overlay_enabled", pressed)
	ProjectSettings.save()

func _on_crt_intensity_changed(value: float) -> void:
	_apply_crt_intensity(value)
	ProjectSettings.set_setting("game/video/crt_effect_strength", value)
	ProjectSettings.save()

func _on_crt_noise_changed(value: float) -> void:
	_apply_crt_noise(value)
	ProjectSettings.set_setting("game/video/crt_noise_amount", value)
	ProjectSettings.save()

func _on_crt_flicker_changed(value: float) -> void:
	_apply_crt_flicker(value)
	ProjectSettings.set_setting("game/video/crt_flicker_amount", value)
	ProjectSettings.save()

func _apply_crt(flag: bool) -> void:
	# Find RC player and apply
	var cars := get_tree().get_nodes_in_group("rc_player")
	if cars.size() > 0:
		var car := cars[0]
		if car and car.has_method("set_crt_enabled"):
			car.set_crt_enabled(flag)

func _apply_crt_intensity(value: float) -> void:
	var cars := get_tree().get_nodes_in_group("rc_player")
	if cars.size() > 0:
		var car := cars[0]
		if car and car.has_method("set_crt_effect_strength"):
			car.set_crt_effect_strength(clamp(value, 0.0, 1.0))

func _apply_crt_noise(value: float) -> void:
	var cars := get_tree().get_nodes_in_group("rc_player")
	if cars.size() > 0:
		var car := cars[0]
		if car and car.has_method("set_crt_noise_amount"):
			car.set_crt_noise_amount(clamp(value, 0.0, 1.0))

func _apply_crt_flicker(value: float) -> void:
	var cars := get_tree().get_nodes_in_group("rc_player")
	if cars.size() > 0:
		var car := cars[0]
		if car and car.has_method("set_crt_flicker_amount"):
			car.set_crt_flicker_amount(clamp(value, 0.0, 1.0))

# --- Styling helpers to match Audio sliders ---
func _call_style_sliders_deferred() -> void:
	# Defer to ensure nodes are fully ready before applying themes
	call_deferred("_style_crt_sliders")

func _style_crt_sliders() -> void:
	_style_slider(crt_intensity)
	_style_slider(crt_noise)
	_style_slider(crt_flicker)

func _style_slider(s: HSlider) -> void:
	if s == null:
		return
	# Grabber icons used by Audio sliders
	var grabber_normal: Texture2D = load("res://resources/Textures/grabber_rect_48x24.png")
	var grabber_hover: Texture2D = load("res://resources/Textures/grabber_rect_48x24_hover.png")
	var grabber_pressed: Texture2D = load("res://resources/Textures/grabber_rect_48x24_pressed.png")
	# Build a temporary Theme with icons for Slider classes
	var t := Theme.new()
	for cls in [&"HSlider", &"Slider", &"VSlider"]:
		t.set_icon(&"grabber", cls, grabber_normal)
		t.set_icon(&"grabber_highlight", cls, grabber_hover)
		t.set_icon(&"grabber_pressed", cls, grabber_pressed)
	s.theme = t
	# Also apply direct overrides to ensure consistency
	s.add_theme_icon_override("grabber", grabber_normal)
	s.add_theme_icon_override("grabber_highlight", grabber_hover)
	s.add_theme_icon_override("grabber_pressed", grabber_pressed)
	# StyleBoxes to match Audio slider look
	var slider_sb := StyleBoxFlat.new()
	slider_sb.bg_color = Color(1, 0.92549, 0.694118, 1)
	slider_sb.border_width_left = 5
	slider_sb.border_width_top = 5
	slider_sb.border_width_right = 5
	slider_sb.border_width_bottom = 5
	slider_sb.border_color = Color(0.192157, 0.0823529, 0.0666667, 1)
	slider_sb.expand_margin_top = 8.0
	slider_sb.expand_margin_bottom = 8.0
	s.add_theme_stylebox_override("slider", slider_sb)
	var grab_area := StyleBoxFlat.new()
	grab_area.bg_color = Color(0.192157, 0.0823529, 0.0666667, 1)
	s.add_theme_stylebox_override("grabber_area", grab_area)
	var grab_area_h := StyleBoxFlat.new()
	grab_area_h.bg_color = Color(0.192157, 0.0823529, 0.0666667, 1)
	s.add_theme_stylebox_override("grabber_area_highlight", grab_area_h)
