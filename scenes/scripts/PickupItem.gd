extends Node3D
# Generic pickup item with proximity label & pickup callbacks.
# Add this root node automatically to group used by player detection.

@export var pickup_prompt: String = ""
@export var carry_offset: Vector3 = Vector3.ZERO  # local offset while on car roof (added after parenting)
@export var disable_process_on_pick: bool = true
# NEW: item metadata
@export var item_type: String = "key"   # e.g. key, crowbar
@export var item_id: String = "red_key"            # specific identifier (e.g. red_key)
# Per-item carry alignment (used by HumanPlayer when carried in hand)
@export var carry_item_offset: Vector3 = Vector3.ZERO
@export var carry_item_rotation_deg: Vector3 = Vector3.ZERO
# Optional: separate visual to use while held in hand (keeps world model intact)
@export var held_model_scene: PackedScene
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

func _ready():
	add_to_group("pickup_item")
	_original_parent = get_parent()
	_area = get_node_or_null("Area3D")
	_label = get_node_or_null("Label3D")
	if _label:
		_label.visible = false
		# Preserve any symbol/text set in the scene; only set if empty
		if str(_label.text) == "":
			_label.text = pickup_prompt
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

func _on_screen_exited() -> void:
	if label_face_player:
		set_process(false)

func is_carried() -> bool:
	return _carried

func can_be_picked() -> bool:
	return not _carried and _player_near

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
	# If a held visual is configured, instance it and hide our existing meshes
	if held_model_scene:
		_create_held_visual()
		_set_meshes_visible(self, false)
		# Optionally apply color override to the held visual too
		if override_material_color_enabled and override_apply_to_held_visual and _held_visual:
			_apply_material_color_override(_held_visual)

func on_dropped(by: Node, apply_throw: bool = true) -> void:
	_carried = false
	# Remove held visual and restore meshes
	if _held_visual and is_instance_valid(_held_visual):
		_held_visual.queue_free()
		_held_visual = null
	_set_meshes_visible(self, true)
	if use_physics and _rb:
		_rb.freeze = false
		_rb.sleeping = false
		if apply_throw:
			var dir := Vector3.ZERO
			var speed := throw_strength
			if by and by is Node3D:
				dir = (by as Node3D).global_transform.basis.z * -1.0
			# Inherit velocity from carrier if available
			if inherit_drop_velocity and by:
				var v
				if by.has_method("get_linear_velocity"):
					v = by.call("get_linear_velocity")
				else:
					v = by.get("linear_velocity")
				if typeof(v) == TYPE_VECTOR3:
					_rb.linear_velocity = v
			if dir != Vector3.ZERO:
				_rb.apply_central_impulse(dir.normalized() * speed * _rb.mass)
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
		if _label: _label.visible = true

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
			for s in sc:
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
