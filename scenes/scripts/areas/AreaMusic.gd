extends Area3D
class_name AreaMusic

@export_group("Music")
@export var music_stream: AudioStream
# Alias for compatibility, not exported (won't show in Inspector)
var stream: AudioStream:
	set(value):
		music_stream = value
	get:
		return music_stream

@export var fade_in: float = 1.0
@export var fade_out: float = 1.0
@export var music_priority: int = 0
@export var loop_music: bool = false
@export var allowed_groups: PackedStringArray = ["human_player"]
@export var allow_rc: bool = false # add "rc_player" dynamically if true
@export var debug_log: bool = false
@export var music_volume_db: float = -10.0

var _inside_count: int = 0
var _id: String = ""

func _ready() -> void:
	monitoring = true
	monitorable = true
	if allow_rc and not allowed_groups.has("rc_player"):
		allowed_groups.append("rc_player")
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))
	_id = str(get_path())
	# Handle bodies already overlapping on start
	for b in get_overlapping_bodies():
		_on_body_entered(b)

func _allowed(body: Node) -> bool:
	if body == null:
		return false
	for g in allowed_groups:
		if body.is_in_group(g):
			return true
	return false

func _current_stream() -> AudioStream:
	return music_stream if music_stream != null else stream

func _on_body_entered(body: Node) -> void:
	if not _allowed(body):
		return
	_inside_count += 1
	if debug_log:
		print("[AreaMusic] enter count=", _inside_count, " by=", body.name)
	var s := _current_stream()
	if _inside_count == 1 and s:
		MusicManager.get_or_create().request_area_music(_id, s, fade_in, music_priority, loop_music, music_volume_db)
	elif _inside_count == 1 and debug_log and s == null:
		print("[AreaMusic] no stream assigned on ", name)

func _on_body_exited(body: Node) -> void:
	if not _allowed(body):
		return
	_inside_count = max(0, _inside_count - 1)
	if debug_log:
		print("[AreaMusic] exit count=", _inside_count, " by=", body.name)
	if _inside_count == 0:
		MusicManager.get_or_create().release_area_music(_id, fade_out)
