extends Node3D
# Attach to any item or prop. When interacted with, shows a popup with hint text.
# Works with HumanPlayer crosshair (try_interact) and optional proximity Area3D.

@export var hint_title: String = "Hint"
@export_multiline var hint_text: String = "This is a hint."
@export var pause_on_show: bool = true
@export var show_only_once: bool = false

# Interaction gating
@export var require_human_crosshair: bool = true
@export var aim_max_distance: float = 6.0
@export var require_interact_press: bool = true

# Proximity (optional)
@export var use_proximity_area: bool = true
@export var use_area_path: NodePath
@export var auto_create_use_area: bool = true
@export var area_size: Vector3 = Vector3(1.3, 1.3, 1.3)

@export var debug_log: bool = false

var _use_area: Area3D
var _players_in_area: Array = []
var _layer: CanvasLayer
var _dialog: AcceptDialog
var _player_to_restore: Node = null
var _shown: bool = false

func _ready():
	if use_proximity_area:
		if use_area_path != NodePath(""):
			_use_area = get_node_or_null(use_area_path) as Area3D
		else:
			_use_area = get_node_or_null("UseArea") as Area3D
		if _use_area == null and auto_create_use_area:
			_use_area = Area3D.new()
			_use_area.name = "UseArea"
			add_child(_use_area)
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = area_size
			cs.shape = shape
			_use_area.add_child(cs)
			_use_area.monitoring = true
			_use_area.monitorable = true
			if debug_log: print("[HintPopup:%s] Auto-created UseArea size=%s" % [name, str(area_size)])
		if _use_area:
			_use_area.body_entered.connect(_on_use_area_body_entered)
			_use_area.body_exited.connect(_on_use_area_body_exited)
	# Listen for proximity interact key
	set_process_unhandled_input(use_proximity_area)

func _on_use_area_body_entered(body: Node) -> void:
	if body and body.is_in_group("player"):
		_players_in_area.append(body)
		if debug_log: print("[HintPopup:%s] Player entered area: %s" % [name, body.name])

func _on_use_area_body_exited(body: Node) -> void:
	_players_in_area.erase(body)
	if debug_log and body: print("[HintPopup:%s] Player exited area: %s" % [name, body.name])

func _unhandled_input(event: InputEvent) -> void:
	if not use_proximity_area or _use_area == null:
		return
	if event.is_action_pressed("interact") and _players_in_area.size() > 0:
		for p in _players_in_area:
			if is_instance_valid(p) and try_interact(p):
				break

# Called by HumanPlayer when crosshair targets this node (or child) and interact is pressed
func try_interact(player: Node) -> bool:
	if show_only_once and _shown:
		return false
	if require_interact_press and not Input.is_action_pressed("interact"):
		return false
	if require_human_crosshair and not _is_crosshair_on_self(player):
		return false
	_show_popup(player)
	return true

func _show_popup(player: Node) -> void:
	_shown = true
	_player_to_restore = player
	if _layer == null or not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.name = "HintPopupLayer"
		_layer.layer = 128
		_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child(_layer)
	if _dialog == null or not is_instance_valid(_dialog):
		_dialog = AcceptDialog.new()
		_dialog.name = "HintDialog"
		_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		_dialog.min_size = Vector2(520, 220)
		# Content
		var text := RichTextLabel.new()
		text.name = "Text"
		text.fit_content = true
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_dialog.add_child(text)
		_layer.add_child(_dialog)
		_dialog.confirmed.connect(_on_dialog_closed)
		if _dialog.has_signal("canceled"):
			_dialog.canceled.connect(_on_dialog_closed)
		_dialog.close_requested.connect(_on_dialog_closed)
	_dialog.title = hint_title
	var lbl := _dialog.get_node("Text") as RichTextLabel
	if lbl:
		lbl.text = hint_text
	_dialog.popup_centered()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pause_on_show:
		get_tree().paused = true
	else:
		if _player_to_restore and _player_to_restore.has_method("set_control_enabled"):
			_player_to_restore.set_control_enabled(false)
	if debug_log:
		print("[HintPopup:%s] Shown. Paused=%s" % [name, str(pause_on_show)])

func _on_dialog_closed() -> void:
	if pause_on_show:
		get_tree().paused = false
	else:
		if _player_to_restore and _player_to_restore.has_method("set_control_enabled"):
			_player_to_restore.set_control_enabled(true)
	_player_to_restore = null
	if _dialog:
		_dialog.hide()
	if debug_log: print("[HintPopup:%s] Closed" % name)

# Helpers (based on other interactables)
func _get_player_camera(player: Node) -> Camera3D:
	if "camera_3d" in player and player.camera_3d is Camera3D:
		return player.camera_3d
	if "_cam" in player and player._cam is Camera3D:
		return player._cam
	var direct := player.get_node_or_null("Camera3D")
	if direct is Camera3D:
		return direct
	var pivots = ["Pivot", "CameraPivot"]
	for p in pivots:
		var pivot = player.get_node_or_null(p)
		if pivot:
			var cam = pivot.get_node_or_null("Camera3D")
			if cam is Camera3D:
				return cam
	var q: Array = []
	for c in player.get_children(): q.append(c)
	while q.size() > 0:
		var n = q.pop_front()
		if n is Camera3D: return n
		for c2 in n.get_children(): q.append(c2)
	return null

func _is_crosshair_on_self(player: Node) -> bool:
	# Non-human interactors are allowed without crosshair gating
	if not (player is CharacterBody3D):
		return true
	var cam := _get_player_camera(player)
	if cam == null:
		return false
	var vp := cam.get_viewport()
	if vp == null:
		return false
	var center: Vector2 = vp.get_visible_rect().size * 0.5
	var origin: Vector3 = cam.project_ray_origin(center)
	var dir: Vector3 = cam.project_ray_normal(center)
	var to: Vector3 = origin + dir * aim_max_distance
	var params := PhysicsRayQueryParameters3D.create(origin, to)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.exclude = [player]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if not hit or not hit.has("collider"):
		return false
	var n: Node = hit["collider"]
	var depth := 0
	while n and depth < 5:
		if n == self:
			return true
		n = n.get_parent(); depth += 1
	return false
