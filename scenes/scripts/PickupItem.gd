extends Node3D
# Generic pickup item with proximity label & pickup callbacks.
# Add this root node automatically to group used by player detection.

@export var pickup_prompt: String = ""
# Device-aware prompt settings
@export_group("Prompt")
@export var prompt_use_device_hint: bool = true
@export var prompt_action: String = "interact" # action to hint
@export var kb_prompt_template: String = "Press {key}"
@export var pad_prompt_template: String = "Press {key}"
@export var kb_font: Font
@export var pad_font: Font
@export var kb_font_size: int = 28
@export var pad_font_size: int = 32
@export_group("")
@export var carry_offset: Vector3 = Vector3.ZERO  # local offset while on car roof (added after parenting)
@export var disable_process_on_pick: bool = true
# NEW: item metadata
@export var item_type: String = "key"   # e.g. key, crowbar
@export var item_id: String = "red_key"            # specific identifier (e.g. red_key)
# Per-item carry alignment (used by HumanPlayer when carried in hand)
@export var carry_item_offset: Vector3 = Vector3.ZERO
@export var carry_item_rotation_deg: Vector3 = Vector3.ZERO
@export var carry_item_scale: Vector3 = Vector3(0.2, 0.2, 0.2) # per-item default; actual human-held scale forced to 0.1 in on_picked_up
# Optional: separate visual to use while held in hand (keeps world model intact)
@export var held_model_scene: PackedScene
# New: make carried items align like the crowbar in-hand
@export var align_in_hand: bool = true
# Hide original model while Human is holding this item
@export var hide_model_when_human_holds: bool = true
# Label facing
@export var label_face_player: bool = true
@export var label_face_yaw_only: bool = true
@export var label_face_flip: bool = true
# Physics behavior
@export var use_physics: bool = true
@export var throw_strength: float = 8.0
@export var inherit_drop_velocity: bool = true
@export var physics_mass: float = 1.0
@export var physics_linear_damp: float = 0.1
@export var physics_angular_damp: float = 0.2
@export var physics_static_body_path: NodePath = NodePath("crowbar_metal_noise_hot_Inst_0/StaticBody3D")
@export var physics_shape_path: NodePath = NodePath("crowbar_metal_noise_hot_Inst_0/StaticBody3D/CollisionShape3D")
# New drop physics tuning
@export var drop_forward_impulse: float = 3.5   # impulse added when dropping (in addition to throw_strength when applied)
@export var drop_upward_impulse: float = 1.2    # small lift so it arcs a bit
@export var drop_random_lateral_impulse: float = 1.0  # random sideways variation
@export var drop_random_torque_impulse: float = 2.0   # random spin impulse
@export var drop_force_scale_with_mass: bool = true   # scale impulses by rigidbody mass
@export var drop_scale_default: float = 0.1  # Default world drop scale for all items (uniform). Adjust to make drops smaller/larger.

# --- Visual override (optional) ---
@export var override_material_color_enabled: bool = false
@export var override_material_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var override_apply_to_held_visual: bool = true

var _carried: bool = false
var _car_ref: Node = null
var _original_parent: Node = null
var _area: Area3D
var _label: Label3D
var _static_body: CollisionObject3D
var _player_near: bool = false
var _rb: RigidBody3D
var _last_carried_state: bool = false
var _held_visual: Node3D = null
var _original_scale: Vector3 = Vector3.ONE
# New: remember the scene’s original scale to restore on drop
var _base_scale: Vector3 = Vector3.ONE

func _ready():
	add_to_group("pickup_item")
	_original_parent = get_parent()
	_area = get_node_or_null("Area3D")
	_label = get_node_or_null("Label3D")
	if _label:
		_label.visible = false
		# Preserve any symbol/text set in the scene if device-aware prompts are disabled
		if not prompt_use_device_hint and str(_label.text) == "":
			_label.text = pickup_prompt
		elif prompt_use_device_hint:
			_update_prompt()
			# Listen for input device changes to live-update label text/font
			var idm := InputDeviceManager.get_or_null()
			if idm and not idm.device_changed.is_connected(_on_device_changed_prompt):
				idm.device_changed.connect(_on_device_changed_prompt)
	_static_body = get_node_or_null("StaticBody3D") as CollisionObject3D
	if use_physics:
		_ensure_rigidbody()
		if _rb:
			_rb.mass = physics_mass
			_rb.linear_damp = physics_linear_damp
			_rb.angular_damp = physics_angular_damp
			# Start frozen to avoid sim cost for idle items lying on the floor
			_rb.freeze = true
			_rb.sleeping = true
	if _area:
		_area.body_entered.connect(_on_body_entered)
		_area.body_exited.connect(_on_body_exited)
	# Only process when visible (for label facing); stays off otherwise
	if label_face_player:
		set_process(false)
		var vis := VisibleOnScreenNotifier3D.new()
		vis.name = "OnScreen"
		add_child(vis)
		vis.screen_entered.connect(_on_screen_entered)
		vis.screen_exited.connect(_on_screen_exited)
	# Ensure we can rotate label toward camera when visible
	if label_face_player or use_physics:
		# Do not enable here; will be toggled by OnScreen signals
		pass
	# Apply optional color override to meshes at startup
	if override_material_color_enabled:
		_apply_material_color_override(self)
	# Capture the initial scene scale so we can always restore to it on drop
	_base_scale = scale

func _process(_delta: float) -> void:
	# Label facing only; avoid any physics toggling here
	if not label_face_player or _label == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		if label_face_yaw_only:
			var to_cam := cam.global_transform.origin - _label.global_transform.origin
			to_cam.y = 0.0
			if to_cam.length() > 0.001:
				_label.look_at(_label.global_transform.origin + to_cam, Vector3.UP)
				if label_face_flip:
					_label.rotate_y(PI)
		else:
			_label.look_at(cam.global_transform.origin, Vector3.UP)
			if label_face_flip:
				_label.rotate_y(PI)
	_last_carried_state = _carried

func _on_screen_entered() -> void:
	if label_face_player:
		set_process(true)
	# Refresh prompt on visibility regain (font sizes may depend on viewport/DPI)
	if _label and prompt_use_device_hint:
		_update_prompt()

func _on_screen_exited() -> void:
	if label_face_player:
		set_process(false)

func is_carried() -> bool:
	return _carried

func can_be_picked() -> bool:
	# Not pickable if currently carried, or not near the player, or if our Area is not monitoring, or node is hidden
	if _carried:
		return false
	if not visible:
		return false
	if _area and not _area.monitoring:
		return false
	return _player_near

func on_picked_up(car: Node, carry_point: Node):
	_carried = true
	_car_ref = car
	_player_near = false
	if _label: _label.visible = false
	if _area: _area.monitoring = false
	# Keep world transform, then parent to carry point and zero local.
	var wt: Transform3D = global_transform
	reparent(carry_point)
	global_transform = wt # maintain orientation
	# Snap to carry point + offset (legacy); HumanPlayer will apply per-item overrides if exported
	transform.origin = carry_offset
	# Disable collisions / processing if desired
	if _static_body:
		_static_body.set_deferred("disabled", true)
	if disable_process_on_pick:
		set_process(false)
		set_physics_process(false)
	if use_physics and _rb:
		_rb.freeze = true
		_rb.linear_velocity = Vector3.ZERO
		_rb.angular_velocity = Vector3.ZERO
	# Save original scale so we can restore it on drop (kept for compatibility)
	_original_scale = scale
	# Decide behavior based on holder type
	var is_human := car != null and car.is_in_group("human_player")
	# If a held visual is configured, only instance it when not hiding for Human
	if held_model_scene and not (is_human and hide_model_when_human_holds):
		_create_held_visual()
		_set_meshes_visible(self, false)
		# Optionally apply color override to the held visual too
		if override_material_color_enabled and override_apply_to_held_visual and _held_visual:
			_apply_material_color_override(_held_visual)
	# If Human and configured to hide, hide meshes and skip visual/alignment
	elif is_human and hide_model_when_human_holds:
		_set_meshes_visible(self, false)
		return
	# Apply in-hand alignment (like crowbar) when carried by the Human (and not hidden)
	if align_in_hand and is_human and not hide_model_when_human_holds:
		if _held_visual and _held_visual is Node3D:
			var rot := Vector3(
				deg_to_rad(carry_item_rotation_deg.x),
				deg_to_rad(carry_item_rotation_deg.y),
				deg_to_rad(carry_item_rotation_deg.z)
			)
			var b := Basis.from_euler(rot)
			# Set local xform of the held visual (force 0.1 scale for Human)
			(_held_visual as Node3D).transform = Transform3D(b.scaled(Vector3(0.1, 0.1, 0.1)), carry_item_offset)
		else:
			# No separate held visual: align the item node itself
			var rot2 := Vector3(
				deg_to_rad(carry_item_rotation_deg.x),
				deg_to_rad(carry_item_rotation_deg.y),
				deg_to_rad(carry_item_rotation_deg.z)
			)
			transform.basis = Basis.from_euler(rot2)
			transform.origin = carry_offset + carry_item_offset
			# Force smaller held scale for Human holders (0.1)
			scale = Vector3(0.1, 0.1, 0.1)

func on_dropped(by: Node, apply_throw: bool = true) -> void:
	_carried = false
	# Remove held visual and restore meshes
	if _held_visual and is_instance_valid(_held_visual):
		_held_visual.queue_free()
		_held_visual = null
	_set_meshes_visible(self, true)
	# Uniform, configurable drop scale for all items
	scale = Vector3.ONE * max(drop_scale_default, 0.01)
	if use_physics and _rb:
		_rb.freeze = false
		_rb.sleeping = false
		var mass_scale := _rb.mass if drop_force_scale_with_mass else 1.0
		if apply_throw:
			# Base directional impulse using throw_strength (legacy behavior)
			var fdir := Vector3.ZERO
			if by and by is Node3D:
				fdir = (by as Node3D).global_transform.basis.z * -1.0
			if fdir != Vector3.ZERO:
				_rb.apply_central_impulse(fdir.normalized() * throw_strength * mass_scale)
		# Always apply supplemental drop physics for a nicer tumble
		var forward := Vector3.ZERO
		if by and by is Node3D:
			forward = (by as Node3D).global_transform.basis.z * -1.0
		# Forward / upward / lateral impulses
		var lateral_rand := Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized() if drop_random_lateral_impulse > 0.0 else Vector3.ZERO
		var impulse := Vector3.ZERO
		impulse += forward.normalized() * drop_forward_impulse * mass_scale if forward != Vector3.ZERO else Vector3.ZERO
		impulse += Vector3.UP * drop_upward_impulse * mass_scale
		impulse += lateral_rand * drop_random_lateral_impulse * mass_scale
		if impulse != Vector3.ZERO:
			_rb.apply_central_impulse(impulse)
		# Random torque for spin
		if drop_random_torque_impulse > 0.0:
			var torque := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized() * drop_random_torque_impulse * mass_scale
			_rb.apply_torque_impulse(torque)
		# Inherit linear velocity from carrier (after impulses so it adds up naturally)
		if inherit_drop_velocity and by:
			var v: Variant = null
			if by.has_method("get_linear_velocity"):
				v = by.call("get_linear_velocity")
			elif "linear_velocity" in by:
				v = by.linear_velocity
			elif by is CharacterBody3D:
				v = (by as CharacterBody3D).velocity
			if typeof(v) == TYPE_VECTOR3:
				_rb.linear_velocity += v
	var wt: Transform3D = global_transform
	# Reparent back to original parent (scene root or container)
	if _original_parent:
		reparent(_original_parent)
	global_transform = wt
	if _static_body:
		_static_body.set_deferred("disabled", false)
	if disable_process_on_pick:
		# Only enable label-facing when it is on screen
		# set_process is toggled by visibility callbacks
		set_physics_process(true)
	if _area:
		_area.monitoring = true
	_car_ref = null

func drop_with_throw(dir: Vector3, strength: float = -1.0) -> void:
	if not (use_physics and _rb):
		return
	var s := strength if strength > 0.0 else throw_strength
	_rb.freeze = false
	_rb.sleeping = false
	if dir != Vector3.ZERO:
		_rb.apply_central_impulse(dir.normalized() * s * _rb.mass)

func _on_body_entered(body: Node):
	if _carried:
		return
	if body.is_in_group("player"):
		_player_near = true
		if _label:
			if prompt_use_device_hint:
				_update_prompt()
			_label.visible = true

func _on_body_exited(body: Node):
	if _carried:
		return
	if body.is_in_group("player"):
		_player_near = false
		if _label: _label.visible = false

func get_item_type() -> String:
	return item_type

func get_item_id() -> String:
	return item_id

func on_stored(by: Node) -> void:
	# Called when placed into a container/inventory (car). Hide label and disable area.
	_carried = false
	_car_ref = by
	_player_near = false
	if _label: _label.visible = false
	if _area: _area.monitoring = false
	# Keep physics disabled while stored/displayed by car
	if _static_body:
		_static_body.set_deferred("disabled", true)
	if use_physics and _rb:
		_rb.freeze = true
		_rb.linear_velocity = Vector3.ZERO
		_rb.angular_velocity = Vector3.ZERO
	# If holder exposes an inventory_hold node, parent there; otherwise, keep current parent
	if by and by.has_method("get_node_or_null"):
		var hold := by.get_node_or_null("InventoryHold")
		if hold and hold is Node3D:
			var wt := global_transform
			reparent(hold)
			global_transform = wt
	# While stored, hide visuals (groups unchanged so roof display can still be found via logic)
	visible = false

func on_removed_from_inventory(_by: Node, _carry_point: Node) -> void:
	# Called when removed from container (e.g., taken from car roof). Re-enable interactions.
	_car_ref = null
	# Restore pickup group and visibility; area monitoring and collisions too
	visible = true
	if _area:
		_area.monitoring = true
	if _static_body:
		_static_body.set_deferred("disabled", false)

func _ensure_rigidbody() -> void:
	# Find an existing RigidBody3D or convert a StaticBody3D if present
	_rb = get_node_or_null("RigidBody3D") as RigidBody3D
	if _rb:
		return
	# Prefer explicitly pointed StaticBody3D if provided
	if physics_static_body_path != NodePath(""):
		var sb_pref := get_node_or_null(physics_static_body_path) as StaticBody3D
		if sb_pref:
			_rb = RigidBody3D.new()
			_rb.name = "RigidBody3D"
			add_child(_rb)
			for child in sb_pref.get_children():
				var cs_pref := child as CollisionShape3D
				if cs_pref:
					var wt_pref: Transform3D = cs_pref.global_transform
					sb_pref.remove_child(cs_pref)
					_rb.add_child(cs_pref)
					cs_pref.global_transform = wt_pref
			sb_pref.queue_free()
			# Done
			return
	# Prefer explicitly pointed CollisionShape3D if provided
	if physics_shape_path != NodePath(""):
		var cs_target := get_node_or_null(physics_shape_path) as CollisionShape3D
		if cs_target:
			_rb = RigidBody3D.new()
			_rb.name = "RigidBody3D"
			add_child(_rb)
			var wt_target: Transform3D = cs_target.global_transform
			(cs_target.get_parent() as Node).remove_child(cs_target)
			_rb.add_child(cs_target)
			cs_target.global_transform = wt_target
			return
	# Scan direct children for any RigidBody3D
	for c in get_children():
		var rb := c as RigidBody3D
		if rb:
			_rb = rb
			break
	if _rb:
		return
	# Convert StaticBody3D to RigidBody3D by moving its shapes
	var static_body := get_node_or_null("StaticBody3D") as StaticBody3D
	if static_body:
		_rb = RigidBody3D.new()
		_rb.name = "RigidBody3D"
		add_child(_rb)
		# Move any CollisionShape3D under the new rigid body, preserving transforms
		for child in static_body.get_children():
			var cs := child as CollisionShape3D
			if cs:
				var wt: Transform3D = cs.global_transform
				static_body.remove_child(cs)
				_rb.add_child(cs)
				cs.global_transform = wt
		static_body.queue_free()
	else:
		# If shapes are directly under this node, move them under a new rigid body
		var found_shapes: Array = []
		for child in get_children():
			var cs2 := child as CollisionShape3D
			if cs2:
				found_shapes.append(cs2)
		if found_shapes.size() > 0:
			_rb = RigidBody3D.new()
			_rb.name = "RigidBody3D"
			add_child(_rb)
			for cs3 in found_shapes:
				var wt2: Transform3D = (cs3 as CollisionShape3D).global_transform
				(cs3.get_parent() as Node).remove_child(cs3)
				_rb.add_child(cs3)
				(cs3 as CollisionShape3D).global_transform = wt2
	if _rb:
		_rb.contact_monitor = true
		_rb.max_contacts_reported = 4

# --- Held visual helpers ---
func _create_held_visual() -> void:
	if not held_model_scene or _held_visual != null:
		return
	var inst := held_model_scene.instantiate()
	if inst and inst is Node3D:
		_held_visual = inst
		add_child(_held_visual)
		_held_visual.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)

func _set_meshes_visible(root: Node, vis: bool) -> void:
	var q: Array = [root]
	while q.size() > 0:
		var n = q.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).visible = vis
		for c in n.get_children():
			q.append(c)

# --- Visual override helper ---
func _apply_material_color_override(root: Node) -> void:
	# Traverse from root and set per-surface override materials tinted to override_material_color.
	var q: Array = [root]
	while q.size() > 0:
		var n = q.pop_back()
		var mi := n as MeshInstance3D
		if mi and mi.mesh:
			var sc := mi.mesh.get_surface_count()
			for s in range(sc):
				var mat: Material = mi.get_surface_override_material(s)
				if mat == null and mi.mesh:
					mat = mi.mesh.surface_get_material(s)
				var out_mat: Material = null
				if mat and mat is BaseMaterial3D:
					out_mat = (mat as BaseMaterial3D).duplicate()
					(out_mat as BaseMaterial3D).albedo_color = override_material_color
				else:
					var std := StandardMaterial3D.new()
					std.albedo_color = override_material_color
					out_mat = std
				mi.set_surface_override_material(s, out_mat)
		for c in n.get_children():
			q.append(c)

func get_base_scale() -> Vector3:
	return _base_scale

func _on_device_changed_prompt(_is_controller: bool, _name: String) -> void:
	if _label and prompt_use_device_hint:
		_update_prompt()

func _update_prompt() -> void:
	if _label == null:
		return
	var use_pad: bool = false
	var idm := InputDeviceManager.get_or_null()
	if idm:
		var v = idm.get("_is_controller_active")
		if typeof(v) == TYPE_BOOL:
			use_pad = v
	var tpl := pad_prompt_template if use_pad else kb_prompt_template
	var txt := InputDeviceManager.format_action(prompt_action, tpl)
	if String(txt) == "" and pickup_prompt != "":
		txt = pickup_prompt
	_label.text = txt
	# Apply font + size for Label3D
	if use_pad and pad_font:
		_label.font = pad_font
	elif (not use_pad) and kb_font:
		_label.font = kb_font
	_label.font_size = pad_font_size if use_pad else kb_font_size
