extends Node3D

@export var light_path: NodePath = NodePath("../SpotLight3D")
@export var toggle_input_action: StringName = "flashlight_toggle"
@export var on_by_default: bool = true
@export var auto_enable_while_held: bool = true
@export var disable_when_dropped: bool = true
@export var energy_on: float = 2.2
@export var energy_off: float = 0.0
@export var fov_degrees: float = 48.0
@export var beam_range: float = 18.0
@export var inner_cone_degrees: float = 8.0
@export var enable_shadows: bool = true
# Battery (optional)
@export var battery_enabled: bool = false
@export var battery_seconds: float = 180.0
@export var low_battery_threshold: float = 15.0
@export var low_battery_flicker: bool = true
@export var debug_log: bool = false

var _light: Light3D
var _is_on: bool = false
var _was_paused: bool = false
var _battery_left: float = 0.0
var _is_carried_cache: bool = false

func _ready():
	_light = get_node_or_null(light_path) as Light3D
	if not _light:
		push_warning("FlashlightItem: Light path not found: %s" % light_path)
	else:
		# Apply base setup safely
		if _light is SpotLight3D:
			var s := _light as SpotLight3D
			s.spot_angle = fov_degrees
			# Set range if available on Spot
			if "range" in s:
				s.range = beam_range
		else:
			# Omni or other Light3D
			if "omni_range" in _light:
				_light.omni_range = beam_range
			elif "range" in _light:
				_light.range = beam_range
		_light.shadow_enabled = enable_shadows
		_battery_left = battery_seconds
		_is_on = on_by_default
		_update_light()

func _process(delta: float) -> void:
	if get_tree().paused:
		_was_paused = true
		return
	# Re-evaluate carried state occasionally
	var carried := _is_carried()
	if carried != _is_carried_cache:
		_is_carried_cache = carried
		if carried and auto_enable_while_held:
			_is_on = true
			_update_light()
		elif not carried and disable_when_dropped:
			_is_on = false
			_update_light()
	# Toggle input only while carried
	if carried and Input.is_action_just_pressed(toggle_input_action):
		_is_on = not _is_on
		if debug_log:
			print("[FlashlightItem:%s] toggled => %s" % [name, _is_on])
		_update_light()
	# Battery drain
	if battery_enabled and carried and _is_on:
		_battery_left = max(0.0, _battery_left - delta)
		if _battery_left <= 0.0 and _is_on:
			_is_on = false
			_update_light()
		elif _battery_left <= low_battery_threshold and low_battery_flicker:
			# Subtle amplitude modulation
			var t := Time.get_ticks_msec() * 0.001
			var flick := 0.85 + 0.15 * sin(t * 17.0) * sin(t * 3.7)
			if _light:
				_light.light_energy = (energy_on * flick) if _is_on else energy_off

func _update_light() -> void:
	if not _light:
		return
	_light.light_energy = energy_on if _is_on else energy_off
	_light.visible = _is_on

# Called by PickupItem if available
func on_picked_up(_p_parent: Node) -> void:
	if auto_enable_while_held:
		_is_on = true
		_update_light()

func on_dropped() -> void:
	if disable_when_dropped:
		_is_on = false
		_update_light()

# Checks if this node is parented under a carrier (human_player / rc_car)
func _is_carried() -> bool:
	var n: Node = self
	while n:
		if n.is_in_group("human_player") or n.is_in_group("rc_car"):
			return true
		n = n.get_parent()
	return false
