extends Area3D
class_name AreaPhase

@export var phase_name: String = "phase_a"
@export var allowed_groups: PackedStringArray = ["human_player"]
@export var allow_rc: bool = false
@export var debug_log: bool = false

var _inside: int = 0
var _id: String = ""

func _ready() -> void:
	monitoring = true
	monitorable = true
	if allow_rc and not allowed_groups.has("rc_player"):
		allowed_groups.append("rc_player")
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))
	_id = str(get_path())
	for b in get_overlapping_bodies():
		_on_body_entered(b)

func _allowed(body: Node) -> bool:
	for g in allowed_groups:
		if body.is_in_group(g):
			return true
	return false

func _on_body_entered(body: Node) -> void:
	if not _allowed(body):
		return
	_inside += 1
	if _inside == 1:
		var r := TapeRouter.get_or_create()
		if r:
			r.push_phase(_id, phase_name)
			if debug_log:
				print("[AreaPhase] enter -> ", phase_name)

func _on_body_exited(body: Node) -> void:
	if not _allowed(body):
		return
	_inside = max(0, _inside - 1)
	if _inside == 0:
		var r := TapeRouter.get_or_create()
		if r:
			r.pop_phase(_id)
			if debug_log:
				print("[AreaPhase] exit")
