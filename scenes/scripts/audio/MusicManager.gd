extends Node
class_name MusicManager

@export var bus_name: String = "Music"
@export var default_volume_db: float = -8.0
@export var crossfade_default: float = 1.0
@export var debug_log: bool = false
# Background music control when area music is active
@export var duck_bg: bool = true
@export var bg_duck_db: float = -80.0
@export var bg_duck_fade: float = 0.6
@export var bg_music_group: String = "bg_music" # optional group to mark background players
@export var bg_music_path: NodePath # optional node (e.g., "/root/BgMusic") to search under
@export var auto_find_bg_by_bus: bool = true # auto-detect any players on this bus_name
@export_enum("Duck","Pause","Stop") var bg_control_mode: int = 0
# New: target background volume when not ducked (≈70% linear)
@export var bg_normal_db: float = -3.1
@export var apply_bg_normal_on_restore: bool = true
@export var crossfade_in_default: float = 2.0
@export var crossfade_out_default: float = 2.0
@export var crossfade_trans: int = Tween.TRANS_SINE
@export var crossfade_ease: int = Tween.EASE_IN_OUT

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _using_a: bool = true
var _fade_tween: Tween

# Looping and per-track volume
var _loop_a: bool = false
var _loop_b: bool = false
var _active_loop: bool = false
var _active_target_db: float = -8.0

# Active selection and registry of area requests
var _active_id: String = ""
var _active_priority: int = -2147483648
var _areas: Dictionary = {} # id -> { stream: AudioStream, priority: int, loop: bool, vol: float }

# Track ducked players to restore later
var _ducked_players: Array = []
var _duck_restore: Dictionary = {} # instance_id -> { vol: float, paused: bool, was_playing: bool, pos: float }

static func get_or_create() -> MusicManager:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var root: Viewport = tree.root
	var mm: MusicManager = root.get_node_or_null("MusicManager") as MusicManager
	if mm == null:
		mm = MusicManager.new()
		mm.name = "MusicManager"
		root.add_child(mm)
		mm._ensure_players()
	return mm

func _ensure_players() -> void:
	if _player_a == null or not is_instance_valid(_player_a):
		_player_a = AudioStreamPlayer.new()
		_player_a.name = "MusicA"
		_player_a.bus = bus_name
		_player_a.volume_db = -80.0
		add_child(_player_a)
		_player_a.finished.connect(Callable(self, "_on_player_finished").bind(_player_a))
	if _player_b == null or not is_instance_valid(_player_b):
		_player_b = AudioStreamPlayer.new()
		_player_b.name = "MusicB"
		_player_b.bus = bus_name
		_player_b.volume_db = -80.0
		add_child(_player_b)
		_player_b.finished.connect(Callable(self, "_on_player_finished").bind(_player_b))

func _on_player_finished(p: AudioStreamPlayer) -> void:
	if p == _player_a and _loop_a:
		p.play()
	elif p == _player_b and _loop_b:
		p.play()

func _get_cur() -> AudioStreamPlayer:
	return _player_a if _using_a else _player_b

func _get_next() -> AudioStreamPlayer:
	return _player_b if _using_a else _player_a

func _set_loop_for_player(p: AudioStreamPlayer, loop: bool) -> void:
	if p == _player_a:
		_loop_a = loop
	elif p == _player_b:
		_loop_b = loop

func request_area_music(id: String, stream: AudioStream, fade_in: float = -1.0, priority: int = 0, loop: bool = false, vol_db: float = -9999.0) -> void:
	if stream == null:
		return
	_ensure_players()
	var was_inactive: bool = _areas.is_empty()
	var tgt_db: float = vol_db if vol_db != -9999.0 else default_volume_db
	_areas[id] = { "stream": stream, "priority": priority, "loop": loop, "vol": tgt_db }
	if debug_log:
		print("[MusicManager] request id=", id, " prio=", priority, " loop=", loop, " vol=", tgt_db, " areas=", _areas.size())
	# Choose highest-priority active
	var best_id: String = id
	var best_prio: int = priority
	for k in _areas.keys():
		var kid: String = String(k)
		var prio: int = int(_areas[kid]["priority"])
		if prio > best_prio:
			best_prio = prio
			best_id = kid
	var best_stream: AudioStream = _areas[best_id]["stream"] as AudioStream
	var best_loop: bool = bool(_areas[best_id].get("loop", false))
	var best_db: float = float(_areas[best_id].get("vol", default_volume_db))
	if _active_id != best_id or _get_cur().stream != best_stream:
		_active_id = best_id
		_active_priority = best_prio
		_active_loop = best_loop
		_active_target_db = best_db
		_crossfade_to(best_stream, fade_in if fade_in >= 0.0 else crossfade_default)
	# If this is the first active area, duck BG now
	if was_inactive:
		_set_duck_state(true)

func release_area_music(id: String, fade_out: float = -1.0) -> void:
	_ensure_players()
	if _areas.has(id):
		_areas.erase(id)
	if debug_log:
		print("[MusicManager] release id=", id, " remain=", _areas.size())
	if id != _active_id:
		# If still some areas remain, nothing else to do
		if _areas.is_empty():
			_set_duck_state(false)
		return
	# Recompute best or stop
	var best_id: String = ""
	var best_prio: int = -2147483648
	for k in _areas.keys():
		var kid: String = String(k)
		var prio: int = int(_areas[kid]["priority"])
		if prio > best_prio:
			best_prio = prio
			best_id = kid
	if best_id == "":
		# No areas: fade out and restore BG
		_crossfade_to(null, fade_out if fade_out >= 0.0 else crossfade_default)
		_active_id = ""
		_active_priority = -2147483648
		_active_loop = false
		_active_target_db = default_volume_db
		_set_duck_state(false)
	else:
		var next_stream: AudioStream = _areas[best_id]["stream"] as AudioStream
		var next_loop: bool = bool(_areas[best_id].get("loop", false))
		var next_db: float = float(_areas[best_id].get("vol", default_volume_db))
		_active_id = best_id
		_active_priority = best_prio
		_active_loop = next_loop
		_active_target_db = next_db
		_crossfade_to(next_stream, crossfade_default)
		# Keep BG ducked since an area is still active

func _crossfade_to(stream: AudioStream, duration: float) -> void:
	_ensure_players()
	# Pick per-direction default when duration not provided
	if duration < 0.0:
		duration = crossfade_out_default if stream == null else crossfade_in_default
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
	var cur: AudioStreamPlayer = _get_cur()
	var nxt: AudioStreamPlayer = _get_next()
	if stream == null:
		# Fade out current and stop
		if duration <= 0.0:
			cur.stop()
			cur.volume_db = -80.0
			return
		_fade_tween = create_tween()
		_fade_tween.set_trans(crossfade_trans).set_ease(crossfade_ease)
		_fade_tween.tween_property(cur, "volume_db", -80.0, duration)
		_fade_tween.finished.connect(func():
			cur.stop()
		)
		return
	# If already playing same stream on current, just ease volume to target
	if cur.stream == stream and cur.playing:
		var target_db: float = _active_target_db
		if abs(cur.volume_db - target_db) > 0.01:
			var tw := create_tween()
			tw.set_trans(crossfade_trans).set_ease(crossfade_ease)
			# Shorter smoothing when not switching streams
			tw.tween_property(cur, "volume_db", target_db, max(0.3, min(crossfade_in_default, 1.5)))
		if debug_log:
			print("[MusicManager] same stream; smoothing to target dB")
		return
	# Prepare next
	nxt.stream = stream
	nxt.bus = bus_name
	nxt.volume_db = -80.0
	_set_loop_for_player(nxt, _active_loop)
	nxt.play()
	if duration <= 0.0:
		cur.stop()
		nxt.volume_db = _active_target_db
		_using_a = not _using_a
		return
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.set_trans(crossfade_trans).set_ease(crossfade_ease)
	_fade_tween.tween_property(cur, "volume_db", -80.0, duration)
	_fade_tween.tween_property(nxt, "volume_db", _active_target_db, duration)
	_fade_tween.finished.connect(func():
		cur.stop()
		_using_a = not _using_a
	)

func stop_all(duration: float = -1.0) -> void:
	_areas.clear()
	_crossfade_to(null, duration if duration >= 0.0 else crossfade_default)

# --- BG duck helpers ---
func _collect_players_in(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			if c != _player_a and c != _player_b:
				if not auto_find_bg_by_bus or (c as Object).get("bus") == bus_name:
					out.append(c)
		# Recurse
		_collect_players_in(c, out)

func _collect_bg_players() -> Array:
	var res: Array = []
	var root: Viewport = get_tree().root
	# By explicit path first (highest priority selection)
	if bg_music_path != NodePath(""):
		var node: Node = root.get_node_or_null(bg_music_path)
		if node:
			if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
				if node != _player_a and node != _player_b:
					res.append(node)
			else:
				_collect_players_in(node, res)
		return res
	# By group next
	if bg_music_group != "":
		var nodes: Array = get_tree().get_nodes_in_group(bg_music_group)
		for n in nodes:
			var p2d: AudioStreamPlayer = n as AudioStreamPlayer
			var p3d: AudioStreamPlayer3D = n as AudioStreamPlayer3D
			if p2d and p2d != _player_a and p2d != _player_b:
				res.append(p2d)
			elif p3d:
				res.append(p3d)
		if not res.is_empty():
			return res
	# Fallback: auto-find by bus across the whole tree (handles Autoload background music)
	if auto_find_bg_by_bus:
		_collect_players_in(root, res)
	return res

func _tween_volume(node: Node, to_db: float, duration: float) -> void:
	if duration <= 0.0:
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).volume_db = to_db
		elif node is AudioStreamPlayer3D:
			(node as AudioStreamPlayer3D).volume_db = to_db
		return
	var tw: Tween = create_tween()
	tw.tween_property(node, "volume_db", to_db, duration)

func _set_duck_state(enable: bool) -> void:
	if not duck_bg:
		return
	if enable:
		if not _ducked_players.is_empty():
			return
		_ensure_players()
		var players: Array = _collect_bg_players()
		for p in players:
			if p == null or not is_instance_valid(p):
				continue
			var iid: int = (p as Object).get_instance_id()
			var orig_vol: float = 0.0
			var was_playing: bool = false
			var pos: float = 0.0
			if p is AudioStreamPlayer:
				var pp: AudioStreamPlayer = p
				orig_vol = pp.volume_db
				was_playing = pp.playing
				pos = pp.get_playback_position()
			elif p is AudioStreamPlayer3D:
				var p3: AudioStreamPlayer3D = p
				orig_vol = p3.volume_db
				was_playing = p3.playing
				pos = p3.get_playback_position()
			_duck_restore[iid] = { "vol": orig_vol, "paused": false, "was_playing": was_playing, "pos": pos }
			match bg_control_mode:
				0: # Duck -> fade to mute only
					_tween_volume(p, bg_duck_db, bg_duck_fade)
				1: # Pause -> fade to mute, then pause
					var tw_pause: Tween = create_tween()
					tw_pause.tween_property(p, "volume_db", bg_duck_db, bg_duck_fade)
					tw_pause.finished.connect(func():
						if p and is_instance_valid(p):
							if p is AudioStreamPlayer:
								(p as AudioStreamPlayer).stream_paused = true
							elif p is AudioStreamPlayer3D:
								(p as AudioStreamPlayer3D).stream_paused = true
					)
				2: # Stop -> fade to mute, then stop
					var tw_stop: Tween = create_tween()
					tw_stop.tween_property(p, "volume_db", -80.0, bg_duck_fade)
					tw_stop.finished.connect(func():
						if p and is_instance_valid(p) and was_playing:
							(p as Object).call("stop")
					)
		_ducked_players = players
		if debug_log:
			print("[MusicManager] BG control enabled mode=", bg_control_mode, " players=", players.size())
	else:
		if _ducked_players.is_empty():
			return
		for p in _ducked_players:
			if p != null and is_instance_valid(p):
				var iid: int = (p as Object).get_instance_id()
				var rec: Dictionary = _duck_restore.get(iid, {})
				match bg_control_mode:
					0: # Duck -> restore volume
						var target_db: float = bg_normal_db if apply_bg_normal_on_restore else float(rec.get("vol", 0.0))
						_tween_volume(p, target_db, bg_duck_fade)
					1: # Pause -> unpause and fade up
						if p is AudioStreamPlayer:
							(p as AudioStreamPlayer).stream_paused = false
						elif p is AudioStreamPlayer3D:
							(p as AudioStreamPlayer3D).stream_paused = false
						var target_db_p: float = bg_normal_db if apply_bg_normal_on_restore else float(rec.get("vol", 0.0))
						_tween_volume(p, target_db_p, bg_duck_fade)
					2: # Stop -> resume (if it was playing) and fade up
						var was_playing: bool = bool(rec.get("was_playing", false))
						var pos: float = float(rec.get("pos", 0.0))
						if was_playing:
							if p is AudioStreamPlayer:
								(p as AudioStreamPlayer).play(pos)
							elif p is AudioStreamPlayer3D:
								(p as AudioStreamPlayer3D).play(pos)
						var target_db_s: float = bg_normal_db if apply_bg_normal_on_restore else float(rec.get("vol", 0.0))
						_tween_volume(p, target_db_s, bg_duck_fade)
		_ducked_players.clear()
		_duck_restore.clear()
		if debug_log:
			print("[MusicManager] BG control restored mode=", bg_control_mode)
