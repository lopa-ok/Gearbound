extends Control

@export var update_interval: float = 0.25
@export var human_groups: PackedStringArray = ["human_player", "human", "player"]
@export var car_groups: PackedStringArray = ["rc_car", "car", "vehicle"]
@export var show_when_paused: bool = true
@export var label_prefix_human: String = "Human holding: "
@export var label_prefix_car: String = "Car holding: "
@export var debug_log: bool = false
# --- New icon options ---
@export var show_text: bool = false
@export var show_icons: bool = true
@export var icon_folder: String = "res://resources/Icons" # will try <folder>/<item_id>.png
@export var default_icon: Texture2D
@export var icon_overrides: Dictionary = {} # { item_id: Texture2D }
@export var icon_size: Vector2 = Vector2(24, 24)
# --- New: type-based icon control ---
@export var icon_by_type: bool = true
@export var type_icon_folder: String = "res://resources/Icons"
@export var type_icon_overrides: Dictionary = {} # { item_type: Texture2D }
@export var type_icon_fallback_names: Dictionary = {
	"key": "key",
	"crowbar": "crowbar",
	"flashlight": "flashlight",
	"box": "box",
	"generic": "item"
}
@export var show_only_active: bool = true
@export var ignore_groups: PackedStringArray = ["player", "pickup_item"]

var _t: float = 0.0
var _human_label: Label
var _car_label: Label
var _human_icon: TextureRect
var _car_icon: TextureRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS if show_when_paused else Node.PROCESS_MODE_INHERIT
	# Labels: only create if enabled
	if show_text:
		_human_label = get_node_or_null("HumanHold") as Label
		_car_label = get_node_or_null("CarHold") as Label
		if _human_label == null:
			_human_label = Label.new()
			_human_label.name = "HumanHold"
			_human_label.text = label_prefix_human + "-"
			add_child(_human_label)
		if _car_label == null:
			_car_label = Label.new()
			_car_label.name = "CarHold"
			_car_label.text = label_prefix_car + "-"
			add_child(_car_label)
	else:
		# Ensure any pre-existing labels are hidden
		var lh = get_node_or_null("HumanHold") as Label
		if lh: lh.visible = false
		var lc = get_node_or_null("CarHold") as Label
		if lc: lc.visible = false
		_human_label = null
		_car_label = null
	# Icons
	_human_icon = get_node_or_null("HumanIcon") as TextureRect
	_car_icon = get_node_or_null("CarIcon") as TextureRect
	if _human_icon == null:
		_human_icon = TextureRect.new()
		_human_icon.name = "HumanIcon"
		add_child(_human_icon)
	if _car_icon == null:
		_car_icon = TextureRect.new()
		_car_icon.name = "CarIcon"
		add_child(_car_icon)
	# Layout defaults
	_human_icon.position = Vector2(8, 6)
	_car_icon.position = Vector2(8, 26)
	_human_icon.size = icon_size
	_car_icon.size = icon_size
	_human_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_car_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if _human_label: _human_label.position = Vector2(36, 8)
	if _car_label: _car_label.position = Vector2(36, 28)
	# Initial visibility
	if _human_label: _human_label.visible = show_text
	if _car_label: _car_label.visible = show_text
	_human_icon.visible = show_icons
	_car_icon.visible = show_icons

func _process(delta: float) -> void:
	if get_tree().paused and not show_when_paused:
		return
	_t += delta
	if _t < update_interval:
		return
	_t = 0.0
	_update_texts()

func _update_texts() -> void:
	# Determine what each actor holds by inspecting items' _car_ref
	var carried_human: Node = null
	var carried_car: Node = null
	var carrier_human: Node = null
	var carrier_car: Node = null
	var candidates := get_tree().get_nodes_in_group("pickup_item")
	if candidates.is_empty():
		candidates = _collect_pickup_like_nodes(get_tree().root)
	for n in candidates:
		if n == null:
			continue
		if ("_carried" in n and n._carried == true) and ("_car_ref" in n and n._car_ref != null):
			var carrier: Node = n._car_ref
			var role := _classify_carrier(carrier)
			if role == "human" and carried_human == null:
				carried_human = n
				carrier_human = carrier
			elif role == "car" and carried_car == null:
				carried_car = n
				carrier_car = carrier
	# Active detection by camera ancestry (robust, group-agnostic)
	var cam := get_viewport().get_camera_3d()
	var cam_in_human := _is_ancestor_of(carrier_human, cam)
	var cam_in_car := _is_ancestor_of(carrier_car, cam)

	# Build ids/types
	var human_id := _item_id(carried_human)
	var car_id := _item_id(carried_car)
	var human_type := _item_type(carried_human)
	var car_type := _item_type(carried_car)
	# Optional text
	if _human_label:
		_human_label.visible = show_text and (not show_only_active or cam_in_human or (not cam_in_human and not cam_in_car and _get_active_role() == "human"))
		_human_label.text = label_prefix_human + (human_id if human_id != "" else "None")
	if _car_label:
		_car_label.visible = show_text and (not show_only_active or cam_in_car or (not cam_in_human and not cam_in_car and _get_active_role() == "car"))
		_car_label.text = label_prefix_car + (car_id if car_id != "" else "None")
	# Icons: visible only if holding something; prefer camera-ancestry; fallback to active role
	if _human_icon:
		_human_icon.texture = _get_icon_for_type(human_type) if icon_by_type else _get_icon_for_id(human_id)
		var show_h := show_icons and carried_human != null
		if show_only_active:
			if cam_in_human or cam_in_car:
				show_h = show_h and cam_in_human
			else:
				show_h = show_h and (_get_active_role() == "human")
		_human_icon.visible = show_h
	if _car_icon:
		_car_icon.texture = _get_icon_for_type(car_type) if icon_by_type else _get_icon_for_id(car_id)
		var show_c := show_icons and carried_car != null
		if show_only_active:
			if cam_in_human or cam_in_car:
				show_c = show_c and cam_in_car
			else:
				show_c = show_c and (_get_active_role() == "car")
		_car_icon.visible = show_c
	if debug_log and (carried_human or carried_car):
		print("[HoldStatusUI] cam_in_human=", cam_in_human, " cam_in_car=", cam_in_car, " human=", human_id, " car=", car_id)

func _find_actor(groups: PackedStringArray) -> Node:
	for g in groups:
		var nodes := get_tree().get_nodes_in_group(g)
		if nodes.size() > 0:
			return nodes[0]
	return null

func _find_held_item_by_carrier(carrier: Node) -> Node:
	if carrier == null:
		return null
	var candidates := get_tree().get_nodes_in_group("pickup_item")
	if candidates.is_empty():
		candidates = _collect_pickup_like_nodes(get_tree().root)
	for n in candidates:
		if n == null:
			continue
		if ("_carried" in n and n._carried == true) and ("_car_ref" in n and n._car_ref == carrier):
			return n
	return null

func _collect_pickup_like_nodes(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child == null:
			continue
		if ("item_id" in child) or ("_carried" in child):
			out.append(child)
		out += _collect_pickup_like_nodes(child)
	return out

func _item_id(item: Node) -> String:
	if item == null:
		return ""
	if ("item_id" in item):
		return str(item.item_id)
	return item.name

func _item_type(item: Node) -> String:
	if item == null:
		return ""
	if ("item_type" in item):
		return str(item.item_type)
	return "generic"

func _classify_carrier(node: Node) -> String:
	if node == null:
		return ""
	var human_set := _to_lower_set(human_groups)
	var car_set := _to_lower_set(car_groups)
	var ignore_set := _to_lower_set(ignore_groups)
	var n: Node = node
	while n:
		var ng := _to_lower_set(n.get_groups())
		# Remove ignored
		for g in ignore_set:
			ng.erase(g)
		if _has_any(ng, human_set):
			return "human"
		if _has_any(ng, car_set):
			return "car"
		n = n.get_parent()
	return ""

func _is_in_groups(node: Node, groups: PackedStringArray) -> bool:
	var set_a := _to_lower_set(node.get_groups())
	var set_b := _to_lower_set(groups)
	var ignore_set := _to_lower_set(ignore_groups)
	for g in ignore_set:
		set_a.erase(g)
	return _has_any(set_a, set_b)

func _to_lower_set(arr: PackedStringArray) -> Dictionary:
	var d := {}
	for s in arr:
		d[str(s).to_lower()] = true
	return d

func _has_any(a: Dictionary, b: Dictionary) -> bool:
	for k in b.keys():
		if a.has(k):
			return true
	return false

func _get_icon_for_type(t: String) -> Texture2D:
	if t == "":
		return default_icon
	if type_icon_overrides.has(t) and type_icon_overrides[t] is Texture2D:
		return type_icon_overrides[t]
	var icon_key: String = str(type_icon_fallback_names.get(t, type_icon_fallback_names.get("generic", "item")))
	return _load_icon_from_folder(type_icon_folder, icon_key)

func _get_icon_for_id(id: String) -> Texture2D:
	if id == "":
		return default_icon
	if icon_overrides.has(id) and icon_overrides[id] is Texture2D:
		return icon_overrides[id]
	return _load_icon_from_folder(icon_folder, id)

func _find_dir_case_insensitive(folder: String) -> String:
	# Try exact first
	var test := DirAccess.open(folder)
	if test != null:
		return folder
	# Resolve parent and leaf
	var parent := folder.get_base_dir()
	var leaf := folder.get_file()
	var d := DirAccess.open(parent)
	if d == null:
		return folder
	d.list_dir_begin()
	var entry := d.get_next()
	var found_name := leaf
	while entry != "":
		if d.current_is_dir():
			if entry.to_lower() == leaf.to_lower():
				found_name = entry
				break
		entry = d.get_next()
	d.list_dir_end()
	return parent.path_join(found_name)

func _load_icon_from_folder(folder: String, base: String) -> Texture2D:
	var try_ext := [".png", ".webp", ".jpg", ".jpeg"]
	# Try to find correct-cased folder and file name by scanning the directory
	var real_folder := _find_dir_case_insensitive(folder)
	var d := DirAccess.open(real_folder)
	if d != null:
		d.list_dir_begin()
		var entry := d.get_next()
		var lower_base := base.to_lower()
		var found_path := ""
		while entry != "":
			if not d.current_is_dir():
				var dot := entry.rfind(".")
				var stem := (entry.substr(0, dot) if dot >= 0 else entry)
				var ext := (entry.substr(dot) if dot >= 0 else "")
				if stem.to_lower() == lower_base and ext.to_lower() in try_ext:
					found_path = real_folder.path_join(entry)
					break
			entry = d.get_next()
		d.list_dir_end()
		if found_path != "":
			var tex0 := load(found_path)
			if tex0 is Texture2D:
				return tex0
	# Fallback to direct paths (exact case)
	for ext in try_ext:
		var path := "%s/%s%s" % [folder, base, ext]
		if ResourceLoader.exists(path):
			var tex := load(path)
			if tex is Texture2D:
				return tex
	return default_icon

func _get_active_role() -> String:
	var cam := get_viewport().get_camera_3d()
	var n: Node = cam
	var human_set := _to_lower_set(human_groups)
	var car_set := _to_lower_set(car_groups)
	var ignore_set := _to_lower_set(ignore_groups)
	while n:
		var ng := _to_lower_set(n.get_groups())
		for g in ignore_set:
			ng.erase(g)
		if _has_any(ng, human_set):
			return "human"
		if _has_any(ng, car_set):
			return "car"
		n = n.get_parent()
	return ""

func _is_ancestor_of(ancestor: Node, node: Node) -> bool:
	if ancestor == null or node == null:
		return false
	var n: Node = node
	while n:
		if n == ancestor:
			return true
		n = n.get_parent()
	return false
