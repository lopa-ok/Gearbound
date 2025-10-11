extends Area3D

const CHECKLIST_MENU = preload("res://scenes/ChecklistMenu.tscn")

@onready var interact_icon: Label3D = $"../Label3D"
var checklist_menu: Control = null
var player_inside := false
var _paused_by_checklist := false
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE

# --- Device-aware prompt settings (inspector) ---
@export_group("Prompt")
@export var prompt_use_device_hint: bool = true
@export var prompt_action: String = "interact"
@export var kb_prompt_template: String = ""
@export var pad_prompt_template: String = ""
@export var kb_font: Font
@export var pad_font: Font
@export var kb_font_size: int = 28
@export var pad_font_size: int = 32
@export var fallback_prompt: String = "" # used when device-aware resolve returns empty
@export_group("")

func _ready():
	interact_icon.visible = true
	# If no explicit fallback set, keep whatever is authored on the Label3D (e.g., icon glyph)
	if fallback_prompt == "" and is_instance_valid(interact_icon):
		fallback_prompt = String(interact_icon.text)
	# Initialize prompt text/font based on device
	if prompt_use_device_hint:
		_update_prompt()
		var idm := InputDeviceManager.get_or_null()
		if idm and not idm.device_changed.is_connected(_on_device_changed_prompt):
			idm.device_changed.connect(_on_device_changed_prompt)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if player_inside and Input.is_action_just_pressed("interact"):
		_open_checklist()
	
	if is_instance_valid(checklist_menu) and checklist_menu.visible and Input.is_action_just_pressed("ui_cancel"): # usually Esc
		_close_checklist()
	
	_face_camera()

func _open_checklist():
	_ensure_checklist_menu()
	if not is_instance_valid(checklist_menu):
		return
	checklist_menu.visible = true
	# Pause the game if not already paused
	if not get_tree().paused:
		_paused_by_checklist = true
		_prev_mouse_mode = Input.mouse_mode
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_crosshair_visible(false)

func _close_checklist():
	# We initiated close; just free and cleanup. Do NOT emit 'closed' here to avoid race/null.
	if is_instance_valid(checklist_menu):
		checklist_menu.queue_free()
		checklist_menu = null
	_cleanup_after_close()

func _cleanup_after_close():
	if _paused_by_checklist:
		get_tree().paused = false
		Input.mouse_mode = _prev_mouse_mode
		_set_crosshair_visible(_is_human_active())
		_paused_by_checklist = false

func _ensure_checklist_menu() -> void:
	if not is_instance_valid(checklist_menu):
		var inst := CHECKLIST_MENU.instantiate()
		if inst and inst is Control:
			checklist_menu = inst
			checklist_menu.visible = false
			# Track when it closes itself (emits 'closed' then queue_free())
			if checklist_menu.has_signal("closed"):
				checklist_menu.connect("closed", Callable(self, "_on_checklist_closed"))
			call_deferred("add_child", checklist_menu)  # safe way to add it

func _on_checklist_closed() -> void:
	# Menu freed itself; clear our reference and unpause
	checklist_menu = null
	_cleanup_after_close()

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		player_inside = true
		 # Keep label visible always; refresh text (useful if device changed while away)
		if prompt_use_device_hint:
			_update_prompt()

func _on_body_exited(body: Node):
	if body.is_in_group("player"):
		player_inside = false

# --- Camera-facing helpers ---
func _get_current_camera() -> Camera3D:
	var cam := get_viewport().get_camera_3d()
	return cam

func _face_camera() -> void:
	if not is_instance_valid(interact_icon):
		return
	var cam := _get_current_camera()
	if cam == null:
		return
	var cam_pos: Vector3 = cam.global_transform.origin
	var label_pos: Vector3 = interact_icon.global_transform.origin
	var dir := cam_pos - label_pos
	# Constrain to yaw so the label doesn't pitch/roll
	dir.y = 0.0
	if dir.length() < 0.0001:
		return
	interact_icon.look_at(label_pos + dir, Vector3.UP)
	# Label3D front faces +Z, look_at points -Z -> flip 180° around Y
	interact_icon.rotate_y(PI)

# --- UI helpers (mirrors PauseManager minimal behavior) ---
func _set_crosshair_visible(vis: bool) -> void:
	var did := false
	for p in get_tree().get_nodes_in_group("human_player"):
		if p and p.has_method("_set_crosshair_visible"):
			p.call("_set_crosshair_visible", vis)
			did = true
	if not did:
		for p in get_tree().get_nodes_in_group("human_player"):
			var cross := p.get_node_or_null("CrosshairLayer/Crosshair")
			if cross and cross is CanvasItem:
				(cross as CanvasItem).visible = vis
				did = true
				break

func _is_human_active() -> bool:
	var ps := get_node_or_null("/root/PlayerSwitcher")
	if ps:
		if ps.has_method("is_rc_active"):
			return not ps.is_rc_active()
		if ps.has_method("is_human_active"):
			return ps.is_human_active()
		if "active" in ps:
			var act = ps.get("active")
			return act == &"human" or String(act) == "human"
	for car in get_tree().get_nodes_in_group("rc_player"):
		var cam := car.get_node_or_null("CameraPivot/Camera3D")
		if cam and cam is Camera3D and (cam as Camera3D).current:
			return false
	for human in get_tree().get_nodes_in_group("human_player"):
		var hcam := human.get_node_or_null("Pivot/Camera3D")
		if hcam and hcam is Camera3D and (hcam as Camera3D).current:
			return true
	return false

# --- Device-aware prompt helpers ---
func _on_device_changed_prompt(_is_controller: bool, _name: String) -> void:
	_update_prompt()

func _update_prompt() -> void:
	if not is_instance_valid(interact_icon):
		return
	var use_pad: bool = false
	var idm := InputDeviceManager.get_or_null()
	if idm:
		var v = idm.get("_is_controller_active")
		if typeof(v) == TYPE_BOOL:
			use_pad = v
	var tpl := pad_prompt_template if use_pad else kb_prompt_template
	var txt := InputDeviceManager.format_action(prompt_action, tpl)
	if String(txt) == "":
		txt = fallback_prompt
	interact_icon.text = txt
	# Only override font and size when a font is provided to avoid scaling authored labels
	if use_pad and pad_font:
		interact_icon.font = pad_font
		if pad_font_size > 0:
			interact_icon.font_size = pad_font_size
	elif (not use_pad) and kb_font:
		interact_icon.font = kb_font
		if kb_font_size > 0:
			interact_icon.font_size = kb_font_size
