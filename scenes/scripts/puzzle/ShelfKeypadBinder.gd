extends Node3D

@export var keypad_path: NodePath
@export var shelf_spawners_paths: Array[NodePath] = []
@export var digit_order_paths: Array[NodePath] = [] # optional explicit order of shelves -> digits
@export var item_group_name := "shelf_item"
@export var auto_update_on_ready := true
@export var update_on_spawns := true # listen for spawner signals to update code dynamically
# New: control sync direction and auto-binding
@export var propagate_code_to_spawners := true # set spawners to use keypad digits 0..N-1
@export var write_code_to_keypad := false # if true, compute code from shelves and write back to keypad
# Debug visualization
@export var show_digit_labels := true
@export var label_offset := Vector3(0, 0.35, 0)
@export var label_color_ok := Color(0, 1, 0, 1)
@export var label_color_mismatch := Color(1, 0.3, 0.3, 1)
@export var label_color_unlinked := Color(1, 1, 0, 1)
@export var label_pixel_size := 0.01
# Debug logging
@export var debug_logs := false
func _dbg(msg: String) -> void:
	if debug_logs:
		print("[ShelfKeypadBinder] %s" % msg)

# Helper: check if an Object exposes a given property
func _has_property(obj: Object, prop_name: StringName) -> bool:
	var plist := obj.get_property_list()
	for p in plist:
		if p.get("name") == prop_name:
			return true
	return false

func _ready() -> void:
	_dbg("ready: auto_update_on_ready=%s, propagate_code_to_spawners=%s, update_on_spawns=%s, write_code_to_keypad=%s" % [auto_update_on_ready, propagate_code_to_spawners, update_on_spawns, write_code_to_keypad])
	# Keypad is the source of truth when propagating to spawners; avoid writing shelves -> keypad then.
	if propagate_code_to_spawners:
		_apply_code_driven_spawn()
	# Only write shelves -> keypad when explicitly enabled AND not propagating keypad -> spawners
	if auto_update_on_ready and write_code_to_keypad and not propagate_code_to_spawners:
		_update_keypad_from_shelves()
	if update_on_spawns:
		_connect_spawner_signals()
	_connect_keypad_signals()
	_update_digit_labels()
	_dbg("ready: initialization complete")

func _connect_spawner_signals() -> void:
	var connected := 0
	for p in shelf_spawners_paths:
		var n := get_node_or_null(p)
		if n and n.has_signal("spawn_complete") and not n.is_connected("spawn_complete", Callable(self, "_on_spawner_done")):
			n.connect("spawn_complete", Callable(self, "_on_spawner_done"))
			connected += 1
	_dbg("connected spawn_complete on %d spawners" % connected)

func _connect_keypad_signals() -> void:
	var kp := get_node_or_null(keypad_path)
	if kp and kp.has_signal("code_success") and not kp.is_connected("code_success", Callable(self, "_on_keypad_code_success")):
		kp.connect("code_success", Callable(self, "_on_keypad_code_success"))
		_dbg("connected keypad code_success signal")
	# Also react to live code changes mid-gameplay
	if kp and kp.has_signal("code_changed") and not kp.is_connected("code_changed", Callable(self, "_on_keypad_code_changed")):
		kp.connect("code_changed", Callable(self, "_on_keypad_code_changed"))
		_dbg("connected keypad code_changed signal")
	elif not kp:
		_dbg("keypad signal not connected (keypad=%s)" % [str(kp)])

func _on_keypad_code_success() -> void:
	_dbg("received keypad code_success")
	# When the keypad signals success, re-apply spawn to ensure shelves match digits
	if propagate_code_to_spawners:
		_apply_code_driven_spawn()
	_update_digit_labels()

func _on_keypad_code_changed(_new_code: String) -> void:
	_dbg("received keypad code_changed -> reapply spawns")
	if propagate_code_to_spawners:
		_apply_code_driven_spawn()
	_update_digit_labels()

func _on_spawner_done(_count: int) -> void:
	_dbg("spawner completed with count=%d" % _count)
	# Avoid shelves -> keypad overwrite if we're propagating keypad -> spawners
	if write_code_to_keypad and not propagate_code_to_spawners:
		_update_keypad_from_shelves()
	_update_digit_labels()

func update_keypad_code() -> void:
	_dbg("update_keypad_code invoked (write_code_to_keypad=%s)" % write_code_to_keypad)
	# Back-compat: keep public name but only write when not propagating keypad -> spawners
	if write_code_to_keypad and not propagate_code_to_spawners:
		_update_keypad_from_shelves()
		_update_digit_labels()

func _update_keypad_from_shelves() -> void:
	# Guard: if propagating keypad -> spawners, do not overwrite keypad with shelves
	if propagate_code_to_spawners:
		_dbg("skip _update_keypad_from_shelves: propagate_code_to_spawners is true")
		return
	var keypad := get_node_or_null(keypad_path)
	if keypad == null:
		push_warning("ShelfKeypadBinder: keypad_path not set or invalid")
		_dbg("aborting: keypad node not found")
		return
	var shelves: Array[Node] = _get_shelves()
	if shelves.is_empty():
		push_warning("ShelfKeypadBinder: no shelf spawners provided")
		_dbg("aborting: shelves empty")
		return
	var code := ""
	var counts_debug: Array[int] = []
	for s in shelves:
		var count := _count_items_under(s)
		counts_debug.append(count)
		code += str(clamp(count, 0, 9))
	var set_via := "none"
	if keypad.has_method("set_correct_code"):
		keypad.call("set_correct_code", code)
		set_via = "method:set_correct_code"
	elif _has_property(keypad, "correct_code"):
		keypad.set("correct_code", code)
		set_via = "property:correct_code"
	else:
		push_warning("ShelfKeypadBinder: keypad does not expose 'correct_code'")
	_dbg("computed code='%s' from counts=%s (applied via %s)" % [code, str(counts_debug), set_via])

func _apply_code_driven_spawn() -> void:
	# Ensure each spawner is configured to use keypad digits in order and respawn
	var shelves := _get_shelves()
	_dbg("apply_code_driven_spawn: shelves=%d" % shelves.size())
	for i in range(shelves.size()):
		var sp := shelves[i]
		if sp == null:
			continue
		var had_use := _has_property(sp, "use_keypad_code")
		var had_path := _has_property(sp, "keypad_path")
		var had_idx := _has_property(sp, "code_digit_index")
		if had_use:
			sp.set("use_keypad_code", true)
		if had_path:
			sp.set("keypad_path", keypad_path)
		if had_idx:
			sp.set("code_digit_index", i)
		var respawned := false
		# Trigger a respawn to match the current keypad code
		if sp.has_method("respawn"):
			sp.call("respawn")
			respawned = true
		_dbg("configured spawner '%s' idx=%d props(use=%s,path=%s,idx=%s) respawned=%s" % [sp.name, i, had_use, had_path, had_idx, respawned])

func _get_shelves() -> Array[Node]:
	var shelves: Array[Node] = []
	if digit_order_paths.size() > 0:
		for p in digit_order_paths:
			var n := get_node_or_null(p)
			if n: shelves.append(n)
		_dbg("_get_shelves: using digit_order_paths -> %d shelves" % shelves.size())
	else:
		for p in shelf_spawners_paths:
			var n2 := get_node_or_null(p)
			if n2: shelves.append(n2)
		_dbg("_get_shelves: using shelf_spawners_paths -> %d shelves" % shelves.size())
	return shelves

func _get_keypad_code() -> String:
	var kp := get_node_or_null(keypad_path)
	if kp == null:
		_dbg("_get_keypad_code: keypad not found")
		return ""
	if _has_property(kp, "correct_code"):
		var v := str(kp.get("correct_code"))
		_dbg("_get_keypad_code via property: '%s'" % v)
		return v
	elif kp.has_method("get_correct_code"):
		var v2 := str(kp.call("get_correct_code"))
		_dbg("_get_keypad_code via method: '%s'" % v2)
		return v2
	_dbg("_get_keypad_code: no code property/method found")
	return ""

func _update_digit_labels() -> void:
	if not show_digit_labels:
		_clear_digit_labels()
		return
	var code_str := _get_keypad_code()
	var shelves := _get_shelves()
	_dbg("update_digit_labels: shelves=%d code='%s'" % [shelves.size(), code_str])
	for i in range(shelves.size()):
		var sp: Node = shelves[i]
		if sp == null:
			continue
		var cnt := _count_items_under(sp)
		var target_digit := -1
		if code_str.length() > i and String(code_str[i]).is_valid_int():
			target_digit = int(code_str[i])
		var lbl := _ensure_digit_label(sp)
		var mode := "RND"
		var linked := false
		if _has_property(sp, "use_keypad_code") and bool(sp.get("use_keypad_code")) == true:
			linked = true
			mode = "CODE"
		var txt := "Shelf %d: %d" % [i + 1, cnt]
		if target_digit >= 0:
			txt += " / target %d" % target_digit
		txt += " [%s]" % mode
		lbl.text = txt
		lbl.pixel_size = label_pixel_size
		# Color: green if linked and matches target, yellow if unlinked, red if mismatch
		if linked and target_digit >= 0 and cnt == target_digit:
			lbl.modulate = label_color_ok
		elif not linked:
			lbl.modulate = label_color_unlinked
		else:
			lbl.modulate = label_color_mismatch
		if sp is Node3D and lbl is Label3D:
			var s3 := sp as Node3D
			lbl.global_position = s3.global_position + label_offset
		_dbg("label for '%s': cnt=%d target=%d mode=%s" % [sp.name, cnt, target_digit, mode])

func _ensure_digit_label(sp: Node) -> Label3D:
	var existing: Label3D = null
	if sp.has_node("__DigitLabel"):
		existing = sp.get_node("__DigitLabel") as Label3D
	if existing:
		return existing
	var lbl := Label3D.new()
	lbl.name = "__DigitLabel"
	lbl.pixel_size = label_pixel_size
	if sp is Node:
		sp.add_child(lbl)
	_dbg("created digit label for '%s'" % sp.name)
	return lbl

func _clear_digit_labels() -> void:
	var cleared := 0
	for sp_path in shelf_spawners_paths:
		var sp := get_node_or_null(sp_path)
		if sp and sp.has_node("__DigitLabel"):
			sp.get_node("__DigitLabel").queue_free()
			cleared += 1
	_dbg("cleared %d digit labels" % cleared)

func _count_items_under(root: Node) -> int:
	var total := 0
	# Count nodes in group under this subtree only
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n.is_in_group(item_group_name):
			total += 1
		for c in n.get_children():
			stack.append(c)
	return total
