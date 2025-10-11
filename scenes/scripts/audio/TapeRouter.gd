extends Node
class_name TapeRouter

signal phase_changed(current: String)

@export var default_phase: String = "default"
var _phases: Dictionary = {}  # source_id -> phase

static func get_or_create() -> TapeRouter:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var root: Viewport = tree.root
	var inst: TapeRouter = root.get_node_or_null("TapeRouter") as TapeRouter
	if inst == null:
		inst = TapeRouter.new()
		inst.name = "TapeRouter"
		root.add_child(inst)
	return inst

func _get_active_phase() -> String:
	if _phases.is_empty():
		return default_phase
	# Return the most recently pushed phase
	var keys := _phases.keys()
	return _phases[keys[keys.size() - 1]]

func push_phase(source_id: String, phase: String) -> void:
	_phases[source_id] = phase
	emit_signal("phase_changed", _get_active_phase())

func pop_phase(source_id: String) -> void:
	if _phases.has(source_id):
		_phases.erase(source_id)
	emit_signal("phase_changed", _get_active_phase())

func set_phase_single(phase: String) -> void:
	_phases.clear()
	_phases["global"] = phase
	emit_signal("phase_changed", _get_active_phase())

func get_current_phase() -> String:
	return _get_active_phase()

func get_stream_for(tape: Node) -> AudioStream:
	if tape == null:
		return null
	var phase: String = get_current_phase()
	# Prefer per-node exports if present
	var dict: Dictionary = {}
	if "phase_streams" in tape:
		dict = tape.phase_streams
		if dict.has(phase):
			return dict[phase] as AudioStream
		if dict.has(default_phase):
			return dict[default_phase] as AudioStream
	# Fallback: tape.default_stream, then tape.tape_stream/stream
	if "default_stream" in tape and tape.default_stream != null:
		return tape.default_stream as AudioStream
	if "tape_stream" in tape and tape.tape_stream != null:
		return tape.tape_stream as AudioStream
	if "stream" in tape and tape.stream != null:
		return tape.stream as AudioStream
	return null
