extends VehicleBody3D

const MAX_STEER = 0.6
const ENGINE_POWER = 400
const MAX_SPEED = 35.0   # 🚗 Maximum speed limit

# Engine sound settings
const BASE_PITCH := 0.8
const MAX_PITCH := 2.2
const THROTTLE_VOLUME := -8.0
const ROLLING_VOLUME := -15.0
const MIN_SPEED_FOR_SOUND := 1.0
const MIN_SPINDOWN_TIME := 1.0   # Minimum spindown time
const MAX_SPINDOWN_TIME := 6.0   # Maximum spindown time
const THROTTLE_TIME_FOR_MAX_SPINDOWN := 3.0  # Throttle duration needed for max spindown

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D
@onready var ray: RayCast3D = $CameraPivot/RayCast3D
@onready var engine_sound: AudioStreamPlayer = $EngineSound

# Carry system (single slot)
@export var pickup_radius: float = 2.5
@export var interact_range: float = 4.5
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

func clear_carried_item():
	# Utility so world interaction scripts can safely clear carried item
	carried_item = null

func _ready():
	camera_3d.rotation_degrees = camera_rotation
	engine_sound.pitch_scale = BASE_PITCH
	engine_sound.volume_db = ROLLING_VOLUME
	add_to_group("player")
	if carry_point == null:
		carry_point = Node3D.new()
		carry_point.name = "CarryPoint"
		add_child(carry_point)
		carry_point.position = Vector3(0, 2.2, 0) # above roof
	if inventory_hold == null:
		inventory_hold = Node3D.new()
		inventory_hold.name = "InventoryHold"
		add_child(inventory_hold)
		inventory_hold.visible = false

func _physics_process(delta):
	update_controls(delta)
	update_camera(delta)
	update_engine_audio(delta)
	update_carried_item_transform()
	_update_display_item_transform()
	process_pickup_input()
	process_drop_input()  # NEW: handle dropping
	# Removed process_inventory_input() call because auto-store uses only 'interact'

func update_controls(delta):
	var speed = linear_velocity.length()

	# --- SPEED-SENSITIVE STEERING ---
	var speed_factor = clamp(1.0 - (speed / MAX_SPEED), 0.2, 1.0)
	var dynamic_max_steer = MAX_STEER * speed_factor
	var steering_response = lerp(6.0, 2.0, speed / MAX_SPEED)

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
			var current_spindown_time = MIN_SPINDOWN_TIME + (min(throttle_duration / THROTTLE_TIME_FOR_MAX_SPINDOWN, 1.0) * (MAX_SPINDOWN_TIME - MIN_SPINDOWN_TIME))
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
		if carried_item:
			_drop_item()
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
		if n.has_method("is_carried") and n.is_carried():
			continue
		if n.has_method("can_be_picked") and not n.can_be_picked():
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

func _try_use_carried_on_target() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_transform.origin + Vector3.UP * 1.2
	var to := from + -transform.basis.z.normalized() * interact_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Exclude self so we don't hit the car
	var excl := []
	if self is CollisionObject3D:
		excl.append(self.get_rid())
	query.exclude = excl
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	if hit and hit.has("collider"):
		var target: Node = hit["collider"]
		# Walk up the parent chain (up to 5 levels) to find a node with try_interact
		var n: Node = target
		var depth := 0
		while n and depth < 5:
			if n.has_method("try_interact"):
				if n.try_interact(self):
					return true
			n = n.get_parent()
			depth += 1
	return false
