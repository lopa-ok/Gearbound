extends MeshInstance3D
@export var debug_log: bool = true
@export var press_depth: float = 0.15
@export var press_time: float = 0.10
@export var hold_time: float = 0.06
@export var release_time: float = 0.16
@export var click_sfx: AudioStream
@export var click_volume_db: float = 0.0

## Emits when this keypad button is clicked.
signal pressed(digit: int)

var _manager: Node = null
var _digit: int = -1
var _press_tween: Tween
var _orig_position: Vector3

func _ready() -> void:
	add_to_group("keypad_button")
	_infer_digit_from_name()
	_orig_position = position

func _dbg(msg: String) -> void:
	if debug_log:
		print("[KeypadButton:%s] %s" % [name, msg])

func _infer_digit_from_name() -> void:
	if _digit >= 0:
		return
	var parts := name.split("_")
	if parts.size() > 0 and parts[0].is_valid_int():
		_digit = int(parts[0])
		_dbg("Digit inferred from name => %d" % _digit)

## Called by the KeypadManager after attaching this script.
func setup(manager_ref: Node, digit_value: int) -> void:
	_manager = manager_ref
	_digit = digit_value
	_create_label()
	_create_hit_area()
	_dbg("Setup complete. digit=%d" % _digit)

func press() -> void:
	_infer_digit_from_name()
	_dbg("Pressed. digit=%d" % _digit)
	_play_click_sfx()
	_animate_press()
	emit_signal("pressed", _digit)

func _animate_press() -> void:
	# Kill any existing tween and reset to orig before animating
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	position = _orig_position
	# Move inward along local -Z, clamp to half the local thickness
	var aabb := get_aabb()
	var max_depth: float = max(0.0, min(press_depth, aabb.size.z * 0.5))
	var inward: Vector3 = -transform.basis.z.normalized() * max_depth
	var pressed_pos := _orig_position + inward
	_press_tween = create_tween()
	_press_tween.tween_property(self, "position", pressed_pos, press_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_press_tween.tween_interval(hold_time)
	_press_tween.tween_property(self, "position", _orig_position, release_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func get_digit() -> int:
	return _digit

func try_interact(_player: Node) -> bool:
	# HumanPlayer looks for nodes with try_interact() along the ray hit chain.
	# Trigger on interact just-pressed to avoid repeats.
	if Input.is_action_just_pressed("interact"):
		_dbg("Interact action detected from player -> press()")
		press()
		return true
	return false

func _create_label() -> void:
	if has_node("DigitLabel"):
		return
	var lbl := Label3D.new()
	lbl.name = "DigitLabel"
	lbl.text = str(_digit)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Adjust for your scene scale. Smaller value = smaller text in world units.
	lbl.pixel_size = 0.008
	var aabb := get_aabb()
	var center := aabb.position + aabb.size * 0.5
	# Place label slightly above the top of the mesh.
	lbl.position = Vector3(center.x, aabb.position.y + aabb.size.y + 0.05, center.z)
	add_child(lbl)

func _create_hit_area() -> void:
	# Replace any previous Area3D with a StaticBody3D so Human raycasts hit a body collider.
	if has_node("HitBody"):
		return
	# Clean up any pre-existing Area collider from older versions
	if has_node("HitArea"):
		var old := get_node("HitArea")
		old.queue_free()
	var body := StaticBody3D.new()
	body.name = "HitBody"
	var shape := BoxShape3D.new()
	var aabb := get_aabb()
	shape.size = aabb.size
	var col := CollisionShape3D.new()
	col.shape = shape
	# Offset the collision shape to cover the mesh bounds in local space
	col.position = aabb.position + aabb.size * 0.5
	body.add_child(col)
	add_child(body)
	# Optional: help other systems resolve back to this button
	body.set_meta("keypad_button", self)
	_dbg("Collider created (HitBody) size=%s pos_offset=%s" % [str(shape.size), str(col.position)])

func _on_area_input_event(_camera: Camera3D, event: InputEvent, _click_position: Vector3, _click_normal: Vector3, _shape_idx: int) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_dbg("Mouse click detected -> press()")
		press()

func _ensure_player3d(name_: String) -> AudioStreamPlayer3D:
	var p := get_node_or_null(name_) as AudioStreamPlayer3D
	if p == null:
		p = AudioStreamPlayer3D.new()
		p.name = name_
		add_child(p)
	return p

func _play_click_sfx() -> void:
	if click_sfx == null:
		return
	var p := _ensure_player3d("ClickSFX")
	p.stream = click_sfx
	p.volume_db = click_volume_db
	p.play()
