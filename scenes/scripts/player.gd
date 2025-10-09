extends VehicleBody3D

const WORLD_LAYER := 1 << 0
const HUMAN_LAYER := 1 << 1
const CAR_LAYER := 1 << 2

const MAX_STEER = 0.6
const ENGINE_POWER = 400
const MAX_SPEED = 35.0   # 🚗 Maximum speed limit

# Engine sound settings
const BASE_PITCH := 0.8
const MAX_PITCH := 2.2
const THROTTLE_VOLUME := -8.0
const ROLLING_VOLUME := -15.0
const MIN_SPEED_FOR_SOUND := 1.0
const MIN_SPindown_TIME := 1.0   # Minimum spindown time
const MAX_SPindown_TIME := 6.0   # Maximum spindown time
const THROTTLE_TIME_FOR_MAX_SPindown := 3.0  # Throttle duration needed for max spindown

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D
@onready var ray: RayCast3D = $CameraPivot/RayCast3D
@onready var engine_sound: AudioStreamPlayer = $EngineSound

# Carry system (single slot)
@export var pickup_radius: float = 2.5
@export var interact_range: float = 4.5
@export var instant_center_on_release: bool = true

# Human player support
@export var human_scene: PackedScene
@export var human_node_path: NodePath
var _human: Node = null
var _switch_action_ready: bool = false

# Anti-stuck settings
@export var unstuck_enabled: bool = true
@export var unstuck_speed_threshold: float = 0.2   # m/s considered "stuck"
@export var unstuck_throttle_threshold: float = 0.2
@export var unstuck_min_time: float = 1.2          # seconds before auto nudge
@export var unstuck_upward_boost: float = 3.5      # m/s upward when nudging
@export var unstuck_forward_nudge: float = 2.5     # m/s along throttle direction
@export var auto_flip_time: float = 1.0            # seconds upside-down before auto flip
@export var safe_record_interval: float = 0.3
@export var ground_check_distance: float = 2.0
@export var unstuck_clearance_size: Vector3 = Vector3(1.2, 1.2, 2.6)
@export var unstuck_cooldown: float = 1.0

# Impact SFX settings
@export var impact_sfx_enabled: bool = true
@export var impact_sfx_min_prev_speed: float = 6.0   # require previous speed at least this
@export var impact_sfx_min_speed_drop: float = 4.0   # trigger when speed drop >= this
@export var impact_sfx_cooldown: float = 0.35
@export var impact_sfx_bus: StringName = "SFX"
@export var impact_stream: AudioStream
@onready var impact_player: AudioStreamPlayer3D = get_node_or_null("ImpactSFX")

@export var engine_bus_name: StringName = &"Car"

var _impact_cd: float = 0.0
var _prev_speed: float = 0.0

var _stuck_timer: float = 0.0
var _flip_timer: float = 0.0
var _safe_timer: float = 0.0
var _last_safe_transform: Transform3D
var _unstuck_cd: float = 0.0
var _unstuck_shape: BoxShape3D

# Removing unused _unstuck_suppressed to silence warning
# var _unstuck_suppressed: bool = false

var carried_item: Node3D = null
@onready var carry_point: Node3D = get_node_or_null("CarryPoint")

# Inventory system
@export var inventory_max_size: int = 10
var inventory: Array = [] # each entry: { "node": Node3D, "data": Dict }
@onready var inventory_hold: Node3D = get_node_or_null("InventoryHold")
@export var auto_store_items: bool = false  # single-carry mode (was true)
var displayed_inventory_item: Node3D = null  # (legacy single display; kept for compatibility)
# Multi-display settings
@export var max_roof_items: int = 4
@export var roof_item_radius: float = 0.7
@export var roof_item_height_offset: float = 0.0
var _displayed_items: Array = []  # currently shown on roof

# Audio state variables
var current_audio_state := ""
var target_pitch := BASE_PITCH
var target_volume := ROLLING_VOLUME
var engine_smoothing := 3.0
var should_play_audio := false
var engine_momentum := 0.0  # Simulates engine spinning down
var throttle_start_time := 0.0
var throttle_duration := 0.0
var is_throttling := false

# Original camera offset & angle
var camera_offset := Vector3(0, 3.331, -5.679)
var camera_rotation := Vector3(-3.1, 180, 0)

var _cross_ref: Node = null

@export var auto_decelerate_on_inactive: bool = true
@export var inactive_decel_rate: float = 12.0
@export var inactive_angular_decel_rate: float = 8.0
@export var engine_audio_fade_speed: float = 6.0
@export var engine_sfx_path: NodePath

var _is_active_rc: bool = false
var _engine_sfx: AudioStreamPlayer3D = null

var _last_carried_item: Node = null
var _suppress_audio_until_inactive: bool = false

# SWITCHING REFACTOR: central PlayerSwitcher drives activation; remove internal TAB handling here
var _switcher: Node = null

@export var scale_multiplier: float = 1.0  # reset to original size (previously 1.5)

@export var highlight_max_distance: float = 0.0  # 0 = use interact_range
var _last_highlight_target: Node = null

@export var switch_fade_in_time: float = 0.25
@export var switch_fade_color: Color = Color(0, 0, 0, 1.0)
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null

var _crt_layer: CanvasLayer = null
var _crt_rect: ColorRect = null
var crt_enabled: bool = true
# CRT overlay tuning
@export var crt_effect_strength: float = 1.0
@export var crt_noise_amount: float = 0.008
@export var crt_flicker_amount: float = 0.02

@export var debug_drop_logs: bool = true

func _get_engine_sfx() -> AudioStreamPlayer3D:
	if _engine_sfx == null or not is_instance_valid(_engine_sfx):
		if engine_sfx_path != NodePath(""):
			_engine_sfx = get_node_or_null(engine_sfx_path) as AudioStreamPlayer3D
		if _engine_sfx == null:
			_engine_sfx = get_node_or_null("EngineSFX") as AudioStreamPlayer3D
	return _engine_sfx

# Hide any crosshair UI when RC is active
func _hide_any_crosshair() -> void:
	# Root-level crosshair created elsewhere
	var root_cross := get_node_or_null("/root/CrosshairUI") as Control
	if root_cross:
		root_cross.visible = false
	# Human-owned crosshair
	if _human == null or not is_instance_valid(_human):
		_find_human_reference()
	if _human:
		if _human.has_method("_set_crosshair_visible"):
			_human.call_deferred("_set_crosshair_visible", false)
		elif _human.has_node("CrosshairLayer/Crosshair"):
			var c := _human.get_node("CrosshairLayer/Crosshair") as Control
			if c:
				c.visible = false

func clear_carried_item():
	# Utility so world interaction scripts can safely clear carried item
	carried_item = null

func _stop_audio_recursive(n: Node) -> void:
	var p3d := n as AudioStreamPlayer3D
	if p3d:
		p3d.stop()
		p3d.volume_db = -80.0
	var p2d := n as AudioStreamPlayer
	if p2d:
		p2d.stop()
		p2d.volume_db = -80.0
	for c in n.get_children():
		_stop_audio_recursive(c)

func _stop_all_car_audio() -> void:
	_stop_audio_recursive(self)

func set_control_enabled(enabled: bool) -> void:
	set_process(enabled)
	# Keep physics processing always on so auto-flip/unstuck can run even when inactive
	set_physics_process(true)
	set_process_input(enabled) # ensure inactive car stops receiving _input (prevents double toggle)

func set_active_camera(active: bool) -> void:
	if camera_3d:
		camera_3d.current = active
	_is_active_rc = active
	if active:
		_mute_car_bus(false)
	else:
		_stop_all_car_audio()
		_mute_car_bus(true)

func _add_child_deferred(p: Node, c: Node) -> void:
	if p and c:
		p.call_deferred("add_child", c)

func _ready():
	_ensure_switch_player_action()
	# Scaling disabled (only applies if changed from 1.0)
	if scale_multiplier != 1.0:
		scale = Vector3.ONE * scale_multiplier
		# Removed radius/range automatic scaling to preserve original tuning
	camera_3d.rotation_degrees = camera_rotation
	engine_sound.pitch_scale = BASE_PITCH
	engine_sound.volume_db = ROLLING_VOLUME
	add_to_group("rc_player")
	# --- Collision setup: avoid car <-> human pushing ---
	collision_layer |= (WORLD_LAYER | CAR_LAYER)
	collision_mask &= ~HUMAN_LAYER
	# ---------------------------------------------------
	# Load saved CRT prefs (persisted via Settings menu)
	if ProjectSettings.has_setting("game/video/crt_overlay_enabled"):
		crt_enabled = bool(ProjectSettings.get_setting("game/video/crt_overlay_enabled"))
	if ProjectSettings.has_setting("game/video/crt_effect_strength"):
		set_crt_effect_strength(float(ProjectSettings.get_setting("game/video/crt_effect_strength")))
	if ProjectSettings.has_setting("game/video/crt_noise_amount"):
		set_crt_noise_amount(float(ProjectSettings.get_setting("game/video/crt_noise_amount")))
	if ProjectSettings.has_setting("game/video/crt_flicker_amount"):
		set_crt_flicker_amount(float(ProjectSettings.get_setting("game/video/crt_flicker_amount")))
	_switcher = get_node_or_null("/root/PlayerSwitcher")
	if _switcher:
		_switcher.connect("active_changed", Callable(self, "_on_active_changed"))
	_on_active_changed(_switcher.active if _switcher else &"rc")

func _ensure_switch_player_action():
	if _switch_action_ready:
		return
	if not InputMap.has_action("switch_player"):
		InputMap.add_action("switch_player")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_TAB
	if not InputMap.action_has_event("switch_player", ev):
		InputMap.action_add_event("switch_player", ev)
	_switch_action_ready = true

func _input(event):
	if not _is_active_rc:
		return # ignore input when inactive to avoid extra toggles
	if event is InputEventKey and event.is_pressed() and event.physical_keycode == KEY_TAB:
		if _switcher:
			var target := &"human" if _switcher.is_rc_active() else &"rc"
			_switcher.set_active(target)

func _on_active_changed(which: StringName):
	var make_active := which == &"rc"
	set_control_enabled(make_active)
	set_active_camera(make_active)
	if make_active:
		_hide_any_crosshair()
		_play_switch_fade_in()
		_ensure_crt_overlay()
	else:
		_cleanup_crt_overlay()

func _physics_process(delta):
	# Always run minimal safety logic even when inactive so auto-flip works
	if unstuck_enabled:
		_update_unstuck(delta)
	# Remaining car-only control when active
	if not _is_active_rc:
		return
	update_controls(delta)
	update_camera(delta)
	update_engine_audio(delta)
	_update_engine_audio_fade(delta)
	process_pickup_input()
	process_drop_input()
	_update_impact_sfx(delta)

func update_controls(delta):
	var speed = linear_velocity.length()

	# --- SPEED-SENSITIVE STEERING ---
	var speed_factor = clamp(1.0 - (speed / MAX_SPEED), 0.2, 1.0)
	var dynamic_max_steer = MAX_STEER * speed_factor
	var steering_response = lerp(6.0, 2.0, speed / MAX_SPEED)

	# Instant centering when both turn keys released
	if instant_center_on_release:
		var left_pressed := Input.is_action_pressed("ui_left")
		var right_pressed := Input.is_action_pressed("ui_right")
		if (Input.is_action_just_released("ui_left") or Input.is_action_just_released("ui_right")) and not left_pressed and not right_pressed:
			steering = 0.0

	steering = move_toward(
		steering,
		Input.get_axis("ui_right", "ui_left") * dynamic_max_steer,
		delta * steering_response
	)

	# --- ENGINE FORCE ---
	var throttle_input = Input.get_axis("ui_down", "ui_up")
	if speed < MAX_SPEED or throttle_input < 0.0:  # allow braking but no accel beyond limit
		engine_force = throttle_input * ENGINE_POWER
	else:
		engine_force = 0.0

func update_camera(delta):
	# Camera pivot follows car
	camera_pivot.global_position = camera_pivot.global_position.lerp(global_position, delta * 20.0)
	camera_pivot.transform = camera_pivot.transform.interpolate_with(transform, delta * 5.0)

	# Camera collision check
	ray.target_position = camera_offset
	var desired_pos = camera_offset
	if ray.is_colliding():
		var hit_pos = ray.get_collision_point()
		var pivot_pos = camera_pivot.global_position
		var dir = camera_offset.normalized()
		var dist = pivot_pos.distance_to(hit_pos) - 0.3
		desired_pos = dir * max(1.0, dist)  # never closer than 1m

	# Smooth camera movement
	camera_3d.position = camera_3d.position.lerp(desired_pos, delta * 10.0)

func update_engine_audio(delta):
	var throttle_input = Input.get_axis("ui_down", "ui_up")
	var speed = linear_velocity.length()
	var abs_throttle = abs(throttle_input)
	var current_unix_time = Time.get_time_dict_from_system().get("unix", 0)
	
	if abs_throttle > 0.05:
		if not is_throttling:
			throttle_start_time = current_unix_time
			is_throttling = true
		throttle_duration = current_unix_time - throttle_start_time
		engine_momentum = 1.0
	else:
		if is_throttling:
			is_throttling = false
		if engine_momentum > 0.0:
			var current_spindown_time = MIN_SPindown_TIME + (min(throttle_duration / THROTTLE_TIME_FOR_MAX_SPindown, 1.0) * (MAX_SPindown_TIME - MIN_SPindown_TIME))
			engine_momentum = max(0.0, engine_momentum - (delta / current_spindown_time))
	
	var new_audio_state = ""
	should_play_audio = false
	
	if abs_throttle > 0.05:
		new_audio_state = "throttle"
		should_play_audio = true
		var throttle_factor = abs_throttle * 0.7
		var speed_factor = min(speed / 40.0, 1.0) * 0.3
		target_pitch = BASE_PITCH + (throttle_factor + speed_factor) * (MAX_PITCH - BASE_PITCH)
		target_volume = THROTTLE_VOLUME
		engine_smoothing = 8.0
	elif engine_momentum > 0.0:
		new_audio_state = "spindown"
		should_play_audio = true
		var momentum_factor = engine_momentum * 0.6
		var speed_factor = min(speed / 30.0, 1.0) * 0.2
		target_pitch = BASE_PITCH + (momentum_factor + speed_factor) * (MAX_PITCH - BASE_PITCH)
		var min_volume = -30.0
		target_volume = lerp(THROTTLE_VOLUME, min_volume, 1.0 - engine_momentum)
		engine_smoothing = 2.0
	else:
		new_audio_state = "silent"
		should_play_audio = false
		engine_smoothing = 3.0
	
	if should_play_audio:
		if not engine_sound.playing:
			engine_sound.play()
		engine_sound.pitch_scale = lerp(engine_sound.pitch_scale, target_pitch, delta * engine_smoothing)
		engine_sound.volume_db = lerp(engine_sound.volume_db, target_volume, delta * engine_smoothing)
	else:
		if engine_sound.playing:
			engine_sound.volume_db = lerp(engine_sound.volume_db, -50.0, delta * 1.0)
			if engine_sound.volume_db < -45.0:
				engine_sound.stop()
	
	current_audio_state = new_audio_state

func _update_engine_audio_fade(delta: float) -> void:
	var sfx := _get_engine_sfx()
	if sfx == null:
		return
	# If suppressed or car is not active, forcefully mute and stop all audio, then exit
	if _suppress_audio_until_inactive or not _is_active_rc:
		_stop_all_car_audio()
		return
	# Active: fade toward target and ensure playback
	var target_db: float = 0.0
	sfx.volume_db = lerp(sfx.volume_db, target_db, clamp(delta * engine_audio_fade_speed, 0.0, 1.0))
	if not sfx.playing:
		sfx.play()

# ===== Carry System =====
func get_carried_item():
	return carried_item

func process_pickup_input():
	# Interact: use carried on target, or swap with nearest (drop current then pick up new), or pick up if empty.
	if Input.is_action_just_pressed("interact"):
		if carried_item:
			if _try_use_carried_on_target():
				return
			var nearest = _get_nearest_pickup_item()
			if nearest and nearest != carried_item:
				var new_item: Node3D = nearest
				_drop_item()
				_pick_up_item(new_item)
			# else: keep holding current item
		else:
			var nearest2 = _get_nearest_pickup_item()
			if nearest2:
				_pick_up_item(nearest2)

# NEW: handle dropping carried or inventory item
func process_drop_input():
	if Input.is_action_just_pressed("drop"):
		if debug_drop_logs:
			print("[RC] drop action pressed. carried_item=", carried_item != null, " inventory_count=", inventory.size())
		if carried_item:
			_drop_item()
			if debug_drop_logs:
				print("[RC] dropped carried item.")
		elif auto_store_items and inventory.size() > 0:
			var idx_to_drop := -1
			if _displayed_items.size() > 0:
				var disp = _displayed_items[0]
				for i in range(inventory.size()):
					if inventory[i]["node"] == disp:
						idx_to_drop = i
						break
			if idx_to_drop == -1:
				idx_to_drop = 0
			if debug_drop_logs:
				print("[RC] dropping inventory index=", idx_to_drop)
			inventory_drop_item(idx_to_drop)

# Auto-store a world item directly into inventory
func _store_world_item(item: Node3D):
	if inventory.size() >= inventory_max_size: return
	# Collect data
	var data := {}
	if item.has_method("get_inventory_data"):
		data = item.get_inventory_data()
	else:
		data = { "name": item.name, "scene": item.scene_file_path if item.has_method("scene_file_path") else "" }
	# Notify item (reuse on_stored if exists, else call on_picked_up for consistency then store)
	if item.has_method("on_stored"):
		item.on_stored(self)
	elif item.has_method("on_picked_up"):
		# Provide carry_point but we immediately hide/store
		item.on_picked_up(self, carry_point)
	# Always append then refresh multi-display
	inventory.append({ "node": item, "data": data })
	_refresh_roof_items()

func _set_displayed_inventory_item(item: Node3D):
	# Kept for backwards compatibility (single-item mode)
	var wt = item.global_transform
	item.reparent(carry_point)
	item.global_transform = wt
	item.visible = true
	item.transform.origin = Vector3.ZERO
	displayed_inventory_item = item

func _update_display_item_transform():
	# Multi display ensure items stay anchored
	for i in _displayed_items:
		if is_instance_valid(i) and i.get_parent() == carry_point:
			i.transform.origin = i.transform.origin  # noop (placeholder if bob/anim added later)
	# Legacy single item support
	if displayed_inventory_item and displayed_inventory_item.get_parent() == carry_point:
		displayed_inventory_item.transform.origin = Vector3.ZERO

func _refresh_roof_items():
	# Clear previous displayed markers
	for it in _displayed_items:
		if is_instance_valid(it) and it.get_parent() == carry_point:
			it.visible = false
	_displayed_items.clear()
	if not auto_store_items:
		return
	# Determine which items to show
	var show_count = min(max_roof_items, inventory.size())
	if show_count == 0:
		displayed_inventory_item = null
		return
	for idx in range(inventory.size()):
		var entry = inventory[idx]
		var item: Node3D = entry["node"]
		if not is_instance_valid(item):
			continue
		if idx < show_count:
			# Place on roof in circle
			var angle = TAU * float(idx) / float(show_count)
			var pos = Vector3(cos(angle) * roof_item_radius, roof_item_height_offset, sin(angle) * roof_item_radius)
			var wt = item.global_transform
			item.reparent(carry_point)
			item.global_transform = wt
			item.visible = true
			item.transform.origin = pos
			_displayed_items.append(item)
		else:
			# Hide extra in hold
			if item.get_parent() != inventory_hold:
				var wt2 = item.global_transform
				item.reparent(inventory_hold)
				item.global_transform = wt2
			item.visible = false
	# Maintain legacy variable to first displayed
	displayed_inventory_item = _displayed_items[0] if _displayed_items.size() > 0 else null

# (Optional) manual retrieval still available via inventory_take_first_item() in code/UI

func process_inventory_input():
	# Deprecated for auto_store mode; keep for potential future UI calls
	pass

func _get_nearest_pickup_item() -> Node3D:
	var nearest: Node3D = null
	var min_d = pickup_radius
	for n in get_tree().get_nodes_in_group("pickup_item"):
		if not n is Node3D: continue
		# Skip items that are carried
		if n.has_method("is_carried") and n.is_carried():
			continue
		# Skip hidden or non-monitoring items (likely stored)
		var skip := false
		if "visible" in n and not n.visible:
			skip = true
		else:
			var ar := n.get_node_or_null("Area3D") as Area3D
			if ar and not ar.monitoring:
				skip = true
		if skip:
			continue
		# Optional: if parented under InventoryHold of the car and not currently on roof display, skip
		var par := n.get_parent()
		if par and par.name == "InventoryHold":
			# Items under InventoryHold are hidden reserve; don't consider them
			continue
		var d = global_position.distance_to(n.global_position)
		if d <= pickup_radius and d < min_d:
			nearest = n
			min_d = d
	return nearest

func _pick_up_item(item: Node3D):
	if carried_item: return
	carried_item = item
	if item.has_method("on_picked_up"):
		item.on_picked_up(self, carry_point)
	else:
		if item.has_method("set_physics_process"):
			item.set_physics_process(false)
		if item.has_method("set_process"):
			item.set_process(false)
		item.reparent(carry_point)
		item.transform.origin = Vector3.ZERO

func _drop_item():
	if not carried_item: return
	var item := carried_item
	if item.has_method("on_dropped"):
		item.on_dropped(self)
	else:
		var world = item.global_transform
		item.reparent(get_parent())
		item.global_transform = world
	carried_item = null
	_place_item_on_ground(item)

func inventory_store_carried_item():
	if not carried_item: return
	if inventory.size() >= inventory_max_size: return
	var data := {}
	if carried_item.has_method("get_inventory_data"):
		data = carried_item.get_inventory_data()
	else:
		data = { "name": carried_item.name, "scene": carried_item.scene_file_path if carried_item.has_method("scene_file_path") else "" }
	# Let item know it's being stored
	if carried_item.has_method("on_stored"):
		carried_item.on_stored(self)
	# Reparent to hidden hold and hide
	var wt = carried_item.global_transform
	carried_item.reparent(inventory_hold)
	carried_item.global_transform = wt
	carried_item.visible = false
	inventory.append({ "node": carried_item, "data": data })
	carried_item = null
	_refresh_roof_items()

# Replace inventory_take_first_item to maintain display
func inventory_take_first_item():
	if inventory.is_empty(): return
	var entry = inventory.pop_front()
	var item: Node3D = entry["node"]
	if not is_instance_valid(item):
		_refresh_roof_items()
		return
	# Remove from roof array if present
	_displayed_items.erase(item)
	if item == displayed_inventory_item:
		displayed_inventory_item = null
	carried_item = item if not auto_store_items else null
	if not auto_store_items:
		item.visible = true
		if item.has_method("on_removed_from_inventory"):
			item.on_removed_from_inventory(self, carry_point)
		else:
			var wt = item.global_transform
			item.reparent(carry_point)
			item.global_transform = wt
			item.transform.origin = Vector3.ZERO
	_refresh_roof_items()

func inventory_remove_item(item: Node3D) -> void:
	if item == null:
		return
	# Remove from inventory array
	var idx := -1
	for i in range(inventory.size()):
		if inventory[i].has("node") and inventory[i]["node"] == item:
			idx = i
			break
	if idx != -1:
		inventory.pop_at(idx)
	# Remove from displayed collections
	_displayed_items.erase(item)
	if displayed_inventory_item == item:
		displayed_inventory_item = null
	# Do not change item's parent/visibility here; the new holder will manage it
	_refresh_roof_items()

func get_inventory_summary() -> Array:
	var summary := []
	for e in inventory:
		var d = e["data"]
		summary.append(d.get("name", "?"))
	return summary

# Optional helper to fully drop an inventory item to world
func inventory_drop_item(index: int):
	if index < 0 or index >= inventory.size(): return
	var entry = inventory.pop_at(index)
	var item: Node3D = entry["node"]
	if not is_instance_valid(item): return
	_displayed_items.erase(item)
	# Base drop position slightly in front & above
	if item.has_method("on_dropped"):
		item.on_dropped(self)
	else:
		item.reparent(get_parent())
	item.visible = true
	if item == displayed_inventory_item:
		displayed_inventory_item = null
	if item.has_method("on_removed_from_inventory"):
		item.on_removed_from_inventory(self, null)
	_place_item_on_ground(item)
	_refresh_roof_items()

func update_carried_item_transform():
	if carried_item and carried_item.get_parent() == carry_point and not carried_item.has_method("on_picked_up"):
		carried_item.transform.origin = Vector3.ZERO

func _place_item_on_ground(item: Node3D):
	if not is_instance_valid(item): return
	var forward := -transform.basis.z.normalized()
	var base_pos := global_transform.origin + forward * 2.0 + Vector3.UP * 1.5
	item.global_position = base_pos
	var space := get_world_3d().direct_space_state
	var from := base_pos
	var to := base_pos - Vector3.UP * 10.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Build exclude list: self (VehicleBody3D has get_rid), plus item's collision body if present
	var exclude := []
	if self is CollisionObject3D:
		exclude.append(self.get_rid())
	var item_body: CollisionObject3D = item if item is CollisionObject3D else item.get_node_or_null("StaticBody3D")
	if item_body and item_body is CollisionObject3D:
		exclude.append(item_body.get_rid())
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit and hit.has("position"):
		item.global_position = hit["position"] + Vector3.UP * 0.05

func _raycast_interact_target(max_dist: float) -> Node:
	# Unified ray used for both highlight and interaction so distances match
	if max_dist <= 0.0:
		max_dist = interact_range
	var space := get_world_3d().direct_space_state
	var from := global_transform.origin + Vector3.UP * 1.2
	var to := from + -transform.basis.z.normalized() * max_dist
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if self is CollisionObject3D:
		query.exclude = [self.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit and hit.has("collider"):
		var node: Node = hit["collider"]
		# Walk up to find interactable (try_interact)
		var depth := 0
		var n: Node = node
		while n and depth < 6:
			if n.has_method("try_interact"):
				return n
			n = n.get_parent()
			depth += 1
	return null

func _try_use_carried_on_target() -> bool:
	var target := _raycast_interact_target(interact_range)
	if target and target.has_method("try_interact"):
		return target.try_interact(self)
	return false

func _update_unstuck(delta: float) -> void:
	# Manual reset only when RC is the active player
	if _is_active_rc and Input.is_action_just_pressed("unstuck") and _last_safe_transform != Transform3D():
		_apply_safe_teleport(_last_safe_transform)
		return

	# Track a safe pose periodically
	_safe_timer += delta
	if _safe_timer >= safe_record_interval:
		_safe_timer = 0.0
		_record_safe_pose()

	# Detect upside-down
	var up_dot: float = global_transform.basis.y.dot(Vector3.UP)
	if up_dot < 0.1:
		_flip_timer += delta
	else:
		_flip_timer = 0.0
	if _flip_timer >= auto_flip_time:
		# Try to place upright near current spot
		var t: Transform3D = global_transform
		t.basis = Basis.from_euler(Vector3(0.0, t.basis.get_euler().y, 0.0))
		t = _ground_snap(t.translated(Vector3.UP * 0.4))
		_apply_safe_teleport(t)
		_flip_timer = 0.0
		return

	# Auto nudge if stuck under throttle (only when RC is active)
	if _is_active_rc:
		var speed: float = linear_velocity.length()
		var throttle: float = abs(Input.get_axis("ui_down", "ui_up"))
		if speed < unstuck_speed_threshold and throttle > unstuck_throttle_threshold:
			_stuck_timer += delta
		else:
			_stuck_timer = 0.0

		if _stuck_timer >= unstuck_min_time:
			# Upward and forward nudge based on throttle direction
			var dir_sign: float = sign(Input.get_axis("ui_down", "ui_up"))
			var forward: Vector3 = -transform.basis.z.normalized() * dir_sign
			var v: Vector3 = linear_velocity
			v.y = max(v.y, unstuck_upward_boost)
			v += forward * unstuck_forward_nudge
			linear_velocity = v
			_stuck_timer = 0.0

func _apply_safe_teleport(base: Transform3D) -> void:
	if _unstuck_cd > 0.0:
		return
	var candidates: Array[Vector3] = [
		Vector3(0, 0.6, 0),
		Vector3(0, 1.0, 0),
		Vector3(0, 1.5, 0),
		Vector3(0, 0.8, 1.2),
		Vector3(0, 0.8, -1.2),
		Vector3(1.2, 0.8, 0),
		Vector3(-1.2, 0.8, 0),
	]
	for off in candidates:
		var t: Transform3D = base
		t.origin += base.basis * off
		t = _ground_snap(t)
		if _is_pose_clear(t):
			global_transform = t
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			_unstuck_cd = unstuck_cooldown
			_stuck_timer = 0.0
			return
	# Fallback: rise up a bit above ground and accept
	var tf: Transform3D = _ground_snap(base.translated(Vector3.UP * 2.0))
	global_transform = tf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_unstuck_cd = unstuck_cooldown
	_stuck_timer = 0.0

func _record_safe_pose() -> void:
	# Consider safe if near ground, mostly upright, and clear
	var t: Transform3D = global_transform
	var up_dot: float = t.basis.y.dot(Vector3.UP)
	if up_dot <= 0.5:
		return
	# Normalize to upright yaw-only
	t.basis = Basis.from_euler(Vector3(0.0, t.basis.get_euler().y, 0.0))
	t = _ground_snap(t)
	if _is_pose_clear(t):
		_last_safe_transform = t

func _ground_snap(t: Transform3D) -> Transform3D:
	var space := get_world_3d().direct_space_state
	var from: Vector3 = t.origin + Vector3.UP * 2.0
	var to: Vector3 = t.origin - Vector3.UP * (ground_check_distance * 5.0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var excl: Array = []
	if self is CollisionObject3D:
		excl.append(self.get_rid())
	q.exclude = excl
	var hit := space.intersect_ray(q)
	if hit and hit.has("position"):
		var pos: Vector3 = hit["position"]
		t.origin.y = pos.y + (unstuck_clearance_size.y * 0.5) + 0.05
	return t

func _is_pose_clear(t: Transform3D) -> bool:
	if _unstuck_shape == null:
		_unstuck_shape = BoxShape3D.new()
		_unstuck_shape.size = unstuck_clearance_size
	else:
		_unstuck_shape.size = unstuck_clearance_size
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _unstuck_shape
	params.transform = t
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var excl: Array = []
	if self is CollisionObject3D:
		excl.append(self.get_rid())
	params.exclude = excl
	var space := get_world_3d().direct_space_state
	var res := space.intersect_shape(params, 4)
	return res.is_empty()

# --- Impact SFX helper ---
func _update_impact_sfx(delta: float) -> void:
	if _impact_cd > 0.0:
		_impact_cd = max(0.0, _impact_cd - delta)
	var cur_speed: float = linear_velocity.length()
	var speed_drop: float = max(0.0, _prev_speed - cur_speed)
	var had_contact := false
	if has_method("get_contact_count"):
		var cc = get_contact_count()
		had_contact = cc > 0
	# Consider also very large drops even if contact count isn't available
	var big_drop := speed_drop >= (impact_sfx_min_speed_drop * 1.5)
	if _impact_cd == 0.0 and impact_player and impact_player.stream and _prev_speed >= impact_sfx_min_prev_speed and speed_drop >= impact_sfx_min_speed_drop and (had_contact or big_drop):
		# Scale volume and pitch by impact strength
		var strength: float = clampf(speed_drop / 12.0, 0.0, 1.0)
		impact_player.volume_db = lerp(-12.0, -2.0, strength)
		var pitch_jitter := 0.1
		impact_player.pitch_scale = 1.0 + (randf() * 2.0 - 1.0) * pitch_jitter
		impact_player.play()
		_impact_cd = impact_sfx_cooldown
		_prev_speed = cur_speed

func _switch_to_human() -> void:
	_ensure_switch_player_action()
	if _human == null or not is_instance_valid(_human):
		_find_human_reference()
	if _human == null:
		return
	if _human.has_method("set_rc_player_path"):
		_human.set_rc_player_path(get_path())
	if _human.has_method("set_control_enabled"):
		_human.set_control_enabled(true)
	if _human.has_method("set_active_camera"):
		_human.set_active_camera(true)
	set_control_enabled(false)
	set_active_camera(false)
	var ps = get_node_or_null("/root/PlayerSwitcher")
	if ps and ps.has_method("set_active"):
		ps.set_active(&"human")

func _get_crosshair() -> Node:
	if _cross_ref == null or not is_instance_valid(_cross_ref):
		_cross_ref = get_node_or_null("/root/CrosshairUI")
		if _cross_ref == null:
			var scr := load("res://scenes/scripts/ui/CrosshairUI.gd")
			if scr:
				var ui: Control = scr.new()
				ui.name = "CrosshairUI"
				get_tree().root.add_child(ui)
				_cross_ref = ui
	return _cross_ref

func _track_item_first_pickup() -> void:
	if not self.has_method("get_carried_item"):
		return
	var cur: Node = self.get_carried_item()
	if cur == _last_carried_item:
		return
	if cur != null:
		_handle_item_pickup_label(cur)
	_last_carried_item = cur

func _handle_item_pickup_label(item: Node) -> void:
	var type_id: String = _get_item_type_for_label(item)
	if type_id == "":
		return
	var tracker := get_node_or_null("/root/PickupTracker")
	var already: bool = tracker != null and tracker.has_shown(type_id)
	if already:
		_hide_item_labels(item)
	else:
		if tracker != null:
			tracker.mark_shown(type_id)

func _get_item_type_for_label(item: Node) -> String:
	if item and item.has_method("get_item_type"):
		return str(item.get_item_type())
	if "item_type" in item:
		return str(item.item_type)
	# Fallback: use class name
	return item.get_class()

func _hide_item_labels(item: Node) -> void:
	for c in item.get_children():
		var lbl := c as Label3D
		if lbl:
			lbl.visible = false

func _ensure_car_bus() -> int:
	var idx := AudioServer.get_bus_index(engine_bus_name)
	if idx == -1:
		AudioServer.add_bus(AudioServer.get_bus_count())
		idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, String(engine_bus_name))
	return idx

func _apply_bus_to_audio(n: Node) -> void:
	var p3d := n as AudioStreamPlayer3D
	if p3d:
		p3d.bus = String(engine_bus_name)
	var p2d := n as AudioStreamPlayer
	if p2d:
		p2d.bus = String(engine_bus_name)
	for c in n.get_children():
		_apply_bus_to_audio(c)

func _set_car_audio_bus() -> void:
	_ensure_car_bus()
	_apply_bus_to_audio(self)

func _mute_car_bus(mute: bool) -> void:
	var idx := _ensure_car_bus()
	AudioServer.set_bus_mute(idx, mute)

func _find_human_reference():
	# Prefer explicit export path
	if human_node_path != NodePath(""):
		_human = get_node_or_null(human_node_path)
	if _human == null:
		# Fallback: first node in human_player group
		var hs = get_tree().get_nodes_in_group("human_player")
		if hs.size() > 0:
			_human = hs[0]

func _process(_delta):
	# Optional crosshair highlight update (only if car active)
	if _is_active_rc:
		var tgt := _raycast_interact_target(highlight_max_distance)
		if tgt != _last_highlight_target:
			# You can hook into your CrosshairUI here if needed, e.g., via a global singleton
			_last_highlight_target = tgt

func _ensure_fade_overlay() -> void:
	if _fade_rect and is_instance_valid(_fade_rect):
		return
	var root := get_tree().root
	if _fade_layer == null or not is_instance_valid(_fade_layer):
		_fade_layer = CanvasLayer.new()
		_fade_layer.name = "SwitchFadeLayer"
		_fade_layer.layer = 128
		root.add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.color = switch_fade_color
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fade_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fade_layer.add_child(_fade_rect)
	# Fill viewport
	_fade_rect.custom_minimum_size = root.size
	_fade_rect.anchor_left = 0
	_fade_rect.anchor_top = 0
	_fade_rect.anchor_right = 1
	_fade_rect.anchor_bottom = 1
	_fade_rect.offset_left = 0
	_fade_rect.offset_top = 0
	_fade_rect.offset_right = 0
	_fade_rect.offset_bottom = 0

func _play_switch_fade_in() -> void:
	_ensure_fade_overlay()
	if _fade_rect == null:
		return
	_fade_rect.visible = true
	_fade_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 0.0, switch_fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.finished.connect(Callable(self, "_cleanup_fade_overlay"))

func _cleanup_fade_overlay() -> void:
	if _fade_rect:
		_fade_rect.visible = false
		_fade_rect.queue_free()
		_fade_rect = null
	if _fade_layer:
		_fade_layer.queue_free()
		_fade_layer = null
	# Also clean CRT if any remains when fade ends
	if not _is_active_rc:
		_cleanup_crt_overlay()

func _ensure_crt_overlay() -> void:
	if not crt_enabled:
		return
	# Reuse any existing root-level overlay to avoid duplicates across scene reloads
	var root := get_tree().root
	if _crt_layer == null or not is_instance_valid(_crt_layer):
		_crt_layer = root.get_node_or_null("CRTPassLayer") as CanvasLayer
	if _crt_layer and is_instance_valid(_crt_layer) and (_crt_rect == null or not is_instance_valid(_crt_rect)):
		_crt_rect = _crt_layer.get_node_or_null("CRTOverlay") as ColorRect
	# If we already have a valid rect, just update params and exit
	if _crt_rect and is_instance_valid(_crt_rect):
		var mat_existing := _crt_rect.material as ShaderMaterial
		if mat_existing:
			mat_existing.set_shader_parameter("screen_alpha", 1.0)
			mat_existing.set_shader_parameter("effect_strength", crt_effect_strength)
			mat_existing.set_shader_parameter("noise_amount", crt_noise_amount)
			mat_existing.set_shader_parameter("flicker_amount", crt_flicker_amount)
		_crt_layer.layer = -100
		_crt_layer.visible = true
		# Fill viewport in case size changed
		_crt_rect.custom_minimum_size = root.size
		_crt_rect.anchor_left = 0
		_crt_rect.anchor_top = 0
		_crt_rect.anchor_right = 1
		_crt_rect.anchor_bottom = 1
		_crt_rect.offset_left = 0
		_crt_rect.offset_top = 0
		_crt_rect.offset_right = 0
		_crt_rect.offset_bottom = 0
		return
	# Otherwise create a new one
	if _crt_layer == null or not is_instance_valid(_crt_layer):
		_crt_layer = CanvasLayer.new()
		_crt_layer.name = "CRTPassLayer"
		# Render below regular UI and pause menu so UI is not affected by CRT
		_crt_layer.layer = -100
		root.add_child(_crt_layer)
	_crt_rect = ColorRect.new()
	_crt_rect.name = "CRTOverlay"
	_crt_rect.color = Color(0,0,0,0) # color ignored by shader
	_crt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crt_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crt_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Shader material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scenes/shaders/CRTCanvas.gdshader")
	mat.set_shader_parameter("screen_alpha", 1.0)
	mat.set_shader_parameter("effect_strength", crt_effect_strength)
	mat.set_shader_parameter("noise_amount", crt_noise_amount)
	mat.set_shader_parameter("flicker_amount", crt_flicker_amount)
	_crt_rect.material = mat
	_crt_layer.add_child(_crt_rect)
	# Fill viewport
	_crt_rect.custom_minimum_size = root.size
	_crt_rect.anchor_left = 0
	_crt_rect.anchor_top = 0
	_crt_rect.anchor_right = 1
	_crt_rect.anchor_bottom = 1
	_crt_rect.offset_left = 0
	_crt_rect.offset_top = 0
	_crt_rect.offset_right = 0
	_crt_rect.offset_bottom = 0

# --- CRT overlay runtime tuning ---
func set_crt_noise_amount(v: float) -> void:
	crt_noise_amount = clampf(v, 0.0, 1.0)
	if _crt_rect and _crt_rect.material is ShaderMaterial:
		(_crt_rect.material as ShaderMaterial).set_shader_parameter("noise_amount", crt_noise_amount)

func set_crt_flicker_amount(v: float) -> void:
	crt_flicker_amount = clampf(v, 0.0, 1.0)
	if _crt_rect and _crt_rect.material is ShaderMaterial:
		(_crt_rect.material as ShaderMaterial).set_shader_parameter("flicker_amount", crt_flicker_amount)

func set_crt_effect_strength(v: float) -> void:
	crt_effect_strength = clampf(v, 0.0, 1.0)
	if _crt_rect and _crt_rect.material is ShaderMaterial:
		(_crt_rect.material as ShaderMaterial).set_shader_parameter("effect_strength", crt_effect_strength)

func set_crt_enabled(flag: bool) -> void:
	crt_enabled = flag
	if not _is_active_rc:
		if _crt_layer:
			_crt_layer.visible = false
		return
	if flag:
		_ensure_crt_overlay()
		if _crt_layer:
			_crt_layer.visible = true
	else:
		_cleanup_crt_overlay()

func is_crt_enabled() -> bool:
	return crt_enabled

func _cleanup_crt_overlay() -> void:
	if _crt_rect:
		_crt_rect.queue_free()
		_crt_rect = null
	if _crt_layer:
		_crt_layer.queue_free()
		_crt_layer = null

func _notification(what):
	if what == NOTIFICATION_PAUSED:
		if _crt_layer:
			_crt_layer.visible = false
	elif what == NOTIFICATION_UNPAUSED:
		if _crt_layer:
			_crt_layer.visible = crt_enabled and _is_active_rc

func _exit_tree():
	# Ensure any root-level overlays are removed when this player is freed (scene restart/menu)
	_cleanup_crt_overlay()
