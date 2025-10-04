extends Node3D

@export var correct_code: String = "1234"
@export var mask_input: bool = false
@export var max_length: int = 4
@export var display_path: NodePath
@export var debug_log: bool = false
# New: validation timing and fail feedback
@export var validate_delay: float = 1.0
@export var flash_times: int = 3
@export var flash_color: Color = Color(1, 0, 0, 1)
@export var flash_duration: float = 0.12
# New: success feedback
@export var success_color: Color = Color(0, 1, 0, 1)
@export var success_hold: float = 0.4

# New: optional link to a KeyDoor node to open on success
@export var target_door_path: NodePath

var entered: String = ""

@onready var display: Node = null
var _validating: bool = false
var _flash_tween: Tween
var _default_modulate: Color = Color(1, 1, 1, 1)

func _dbg(msg: String) -> void:
	if debug_log:
		print("[KeypadManager:%s] %s" % [name, msg])

func _ready() -> void:
	# Use user-provided display if set, else ensure/find/create one.
	display = _ensure_display()
	_capture_default_modulate()
	_update_display()
	# Auto-attach button scripts and wire signals based on child names like "1_button".
	_setup_buttons()
	# Auto-connect success -> door open
	if not is_connected("code_success", Callable(self, "_on_code_success")):
		connect("code_success", Callable(self, "_on_code_success"))

func _ensure_display() -> Node:
	if display_path != NodePath(""):
		var n := get_node_or_null(display_path)
		if n:
			_dbg("Using display via display_path: %s" % n.get_path())
			return n
	# Fallback: look for a child named EnteredLabel
	if has_node("EnteredLabel"):
		var el := get_node("EnteredLabel")
		_dbg("Using child EnteredLabel: %s" % el.get_path())
		return el
	# Try to auto-detect any Label-like child (depth-1 search first, then recursive)
	for c in get_children():
		if c is Label3D or c is Label or c is RichTextLabel:
			_dbg("Auto-detected label child: %s" % c.get_path())
			return c
	# Recursive search
	var q: Array = []
	for c in get_children(): q.push_back(c)
	while q.size() > 0:
		var n: Node = q.pop_front()
		if n is Label3D or n is Label or n is RichTextLabel:
			_dbg("Auto-detected label descendant: %s" % n.get_path())
			return n
		for c2 in n.get_children(): q.push_back(c2)
	# Create a default Label3D above the keypad if nothing found
	var lbl := Label3D.new()
	lbl.name = "EnteredLabel"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.01
	# Position above the keypad body; adjust offsets for your scene.
	var aabb := _compute_children_aabb()
	var center := aabb.position + aabb.size * 0.5
	lbl.position = Vector3(center.x, aabb.position.y + aabb.size.y + 0.2, center.z)
	add_child(lbl)
	_dbg("Created default Label3D: %s" % lbl.get_path())
	return lbl

func _compute_children_aabb() -> AABB:
	var first := true
	var bounds := AABB()
	for c in get_children():
		var mi := c as MeshInstance3D
		if mi:
			var aabb := mi.get_aabb()
			# Transform to world/local combined where needed
			aabb.position = mi.to_global(aabb.position)
			if first:
				bounds = aabb
				first = false
			else:
				bounds = bounds.merge(aabb)
	return bounds if not first else AABB(Vector3.ZERO, Vector3.ONE)

func _setup_buttons() -> void:
	for c in get_children():
		var mi := c as MeshInstance3D
		if not mi:
			continue
		if not c.name.ends_with("_button"):
			continue
		var digit_str := c.name.split("_")[0]
		var digit := int(digit_str)
		# Attach button logic if not present
		if mi.get_script() == null:
			var script := load("res://scenes/scripts/keypad/KeypadButton.gd")
			mi.set_script(script)
			# After setting a script, we can call setup on it
			mi.call_deferred("setup", self, digit)
		# Connect signal if exists
		if not mi.is_connected("pressed", Callable(self, "_on_button_pressed")):
			mi.connect("pressed", Callable(self, "_on_button_pressed"))

func _on_button_pressed(digit: int) -> void:
	_dbg("Button pressed digit=%d" % digit)
	_append_digit(digit)

func _append_digit(d: int) -> void:
	if _validating:
		return
	if entered.length() >= max_length:
		return
	entered += str(d)
	_update_display()
	if entered.length() == max_length:
		_schedule_validate()

func clear() -> void:
	if _validating:
		return
	entered = ""
	_update_display()
	_reset_display_color()

func _update_display() -> void:
	if not display:
		return
	var txt := ("*".repeat(entered.length()) if mask_input else entered)
	if display is Label3D:
		(display as Label3D).text = txt
	elif display is Label:
		(display as Label).text = txt
	elif display is RichTextLabel:
		(display as RichTextLabel).text = txt
	var path_str := "<freed>"
	if is_instance_valid(display):
		path_str = str(display.get_path())
	_dbg("Display updated: '%s' on %s" % [txt, path_str])

func _schedule_validate() -> void:
	if _validating:
		return
	_validating = true
	_dbg("Scheduling validation in %0.2fs" % validate_delay)
	await get_tree().create_timer(max(validate_delay, 0.0)).timeout
	await _validate()
	_validating = false

func _validate() -> void:
	var ok := entered == correct_code
	_dbg("Validating '%s' vs '%s' => %s" % [entered, correct_code, str(ok)])
	if ok:
		_set_display_color(success_color)
		await get_tree().create_timer(max(success_hold, 0.0)).timeout
		emit_signal_success()
		entered = ""
		_update_display()
		_reset_display_color()
	else:
		await _flash_fail()
		emit_signal_fail()
		entered = ""
		_update_display()
		_reset_display_color()

func _capture_default_modulate() -> void:
	if display is Label3D:
		_default_modulate = (display as Label3D).modulate
	elif display is CanvasItem:
		_default_modulate = (display as CanvasItem).modulate
	else:
		_default_modulate = Color(1, 1, 1, 1)

func _set_display_color(col: Color) -> void:
	if not display:
		return
	if display is Label3D:
		(display as Label3D).modulate = col
	elif display is CanvasItem:
		(display as CanvasItem).modulate = col

func _reset_display_color() -> void:
	_set_display_color(_default_modulate)

func _flash_fail() -> void:
	# Stop any previous tween
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	# Build a flashing tween: normal -> red -> normal, repeated
	_flash_tween = create_tween()
	_flash_tween.set_trans(Tween.TRANS_SINE)
	_flash_tween.set_ease(Tween.EASE_IN_OUT)
	for i in range(max(flash_times, 1)):
		_flash_tween.tween_callback(Callable(self, "_set_display_color").bind(flash_color))
		_flash_tween.tween_interval(flash_duration)
		_flash_tween.tween_callback(Callable(self, "_reset_display_color"))
		_flash_tween.tween_interval(flash_duration)
	await _flash_tween.finished

signal code_success()
signal code_fail()

func emit_signal_success():
	emit_signal("code_success")

func emit_signal_fail():
	emit_signal("code_fail")

# ===== KeyDoor integration =====
func _on_code_success() -> void:
	_dbg("Code success -> opening target door")
	var door := _get_target_door()
	if door == null:
		_dbg("No target door found; set target_door_path in the inspector")
		return
	# Prefer a public helper if available
	if door.has_method("open_from_external"):
		door.call("open_from_external")
		return
	# Fallbacks: use internal helpers if present
	if door.has_method("_start_open_helper"):
		door.call("_start_open_helper")
		return
	if door.has_method("_open"):
		door.call("_open")
		return
	_dbg("Target door has no recognizable open method")

func _get_target_door() -> Node:
	if target_door_path != NodePath(""):
		var d := get_node_or_null(target_door_path)
		if d:
			return d
	# Heuristic: search up the tree for a node exposing an open method
	var n := get_parent()
	while n:
		if n.has_method("open_from_external") or n.has_method("_start_open_helper") or n.has_method("_open"):
			return n
		n = n.get_parent()
	return null
