# filepath: /Users/lopa/test/scenes/scripts/interactables/CassettePlayer.gd
extends Node3D
# Cassette player that accepts a held CassetteTape and plays its track.
# Usage:
# - Add this script to your cassette player mesh root.
# - Add (or let it create) a proximity Area3D to gate interaction.
# - Optionally assign an AudioStreamPlayer3D child (or it will create one) for playback.
# - Player presses Interact while holding a tape near the player to insert & play.

@export var use_proximity_area: bool = true
@export var auto_create_use_area: bool = true
@export var use_area_path: NodePath
@export var area_size: Vector3 = Vector3(1.4, 1.0, 1.0)
# Whether human must aim the crosshair at this object to interact
@export var require_human_crosshair: bool = true
@export var aim_max_distance: float = 6.0
@export var require_interact_press: bool = true
@export var debug_log: bool = false
# Only allow the Human to trigger interactions (prevents RC car double-fire)
@export var require_human_actor: bool = true
# New: consume the held tape so it disappears when inserted
@export var consume_tape_after_insert: bool = true
# New: Only handle the Interact input inside this node when true.
# By default, interaction should be driven by the Human raycast calling try_interact(),
# to avoid double-triggering from both sides in the same frame.
@export var proximity_handles_input: bool = false
# New: When interacting while a tape is inserted, eject it back to the player
@export var eject_on_second_interact: bool = true
@export var eject_into_player_hand: bool = true
@export var eject_drop_forward: float = 1.2
@export var eject_drop_up: float = 0.9
# New: scale to apply to the tape when dropping it on eject
@export var eject_drop_scale: float = 1.0

# Audio playback
@export var player_path: NodePath  # optional existing AudioStreamPlayer3D
@export var bus_name: String = "SFX"  # route to SFX bus
@export var volume_db: float = -2.0
@export var bg_music_fade_out_sec: float = 0.8
@export var bg_music_fade_in_sec: float = 0.8
@export var audio_player_path: NodePath
var _audio_node: Node = null

var _use_area: Area3D
var _players_in_area: Array = []
var _asp: AudioStreamPlayer3D
var _inserted_tape: Node = null  # CassetteTape node reference (held item instance)
# New: remember the loaded stream even if the physical tape is consumed
var _loaded_stream: AudioStream = null
# New: snapshot of the consumed tape so we can recreate it on eject
var _consumed_tape_packed: PackedScene = null
# Short cooldown to avoid duplicate toggles when both human and this node trigger in same frame
var _last_interact_ms: int = -1

func _ready():
	# Ensure we receive unhandled input for proximity interaction (only if opted in)
	set_process_unhandled_input(use_proximity_area and proximity_handles_input)
	if debug_log:
		print("[CassettePlayer:%s] _ready: use_proximity_area=%s auto_create=%s require_crosshair=%s proximity_handles_input=%s" % [name, str(use_proximity_area), str(auto_create_use_area), str(require_human_crosshair), str(proximity_handles_input)])
	# Setup/resolve proximity area
	if use_proximity_area:
		if use_area_path != NodePath(""):
			_use_area = get_node_or_null(use_area_path) as Area3D
		else:
			_use_area = get_node_or_null("UseArea") as Area3D
		if _use_area == null and auto_create_use_area:
			_use_area = Area3D.new()
			_use_area.name = "UseArea"
			var shape := CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			(shape.shape as BoxShape3D).size = area_size
			add_child(_use_area)
			_use_area.add_child(shape)
			shape.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
			if debug_log:
				print("[CassettePlayer:%s] Created UseArea with size=%s" % [name, str(area_size)])
		# Always connect signals when area exists (created or pre-existing)
		if _use_area:
			if not _use_area.body_entered.is_connected(_on_use_area_body_entered):
				_use_area.body_entered.connect(_on_use_area_body_entered)
			if not _use_area.body_exited.is_connected(_on_use_area_body_exited):
				_use_area.body_exited.connect(_on_use_area_body_exited)
			if debug_log:
				print("[CassettePlayer:%s] UseArea resolved: monitoring=%s" % [name, str(_use_area.monitoring)])
	# Resolve audio player
	if player_path != NodePath(""):
		_asp = get_node_or_null(player_path) as AudioStreamPlayer3D
	else:
		_asp = get_node_or_null("TapePlayer") as AudioStreamPlayer3D
	if _asp == null:
		_asp = AudioStreamPlayer3D.new()
		_asp.name = "TapePlayer"
		add_child(_asp)
		if debug_log:
			print("[CassettePlayer:%s] Created AudioStreamPlayer3D child 'TapePlayer'" % name)
	# Base audio settings
	if bus_name != "" and _asp:
		_asp.bus = bus_name
	if _asp:
		_asp.volume_db = volume_db
		if debug_log:
			print("[CassettePlayer:%s] Audio setup: bus=%s vol=%.2f stream=%s" % [name, _asp.bus, _asp.volume_db, str(_asp.stream)])

func _unhandled_input(event: InputEvent) -> void:
	if not proximity_handles_input:
		return
	if not use_proximity_area or _use_area == null:
		return
	# ignore echoes
	if event is InputEventAction and event.is_echo():
		return
	if event.is_action_pressed("interact") and _players_in_area.size() > 0:
		if debug_log: print("[CassettePlayer:%s] Interact pressed. players_in_area=%d" % [name, _players_in_area.size()])
		for p in _players_in_area:
			if is_instance_valid(p):
				if debug_log: print("[CassettePlayer:%s] Trying interact with %s" % [name, p.name])
				if try_interact(p):
					break

func _on_use_area_body_entered(body: Node) -> void:
	if body and body.is_in_group("player"):
		_players_in_area.append(body)
		if debug_log: print("[CassettePlayer:%s] Player entered area: %s (count=%d)" % [name, body.name, _players_in_area.size()])

func _on_use_area_body_exited(body: Node) -> void:
	_players_in_area.erase(body)
	if debug_log and body: print("[CassettePlayer:%s] Player exited area: %s (count=%d)" % [name, body.name, _players_in_area.size()])

func try_interact(player: Node) -> bool:
	# Enforce actor type if configured
	if require_human_actor:
		var is_human := player != null and (player.is_in_group("human_player") or player.is_in_group("human"))
		if not is_human:
			if debug_log:
				print("[CassettePlayer:%s] Ignoring try_interact from non-human actor: %s" % [name, str(player)])
			return false
	# De-duplicate interactions fired from both Human and proximity handler in the same moment
	var now_ms := Time.get_ticks_msec()
	if _last_interact_ms >= 0 and now_ms - _last_interact_ms < 120:
		if debug_log:
			print("[CassettePlayer:%s] Ignoring duplicate try_interact (dt=%dms)" % [name, now_ms - _last_interact_ms])
		return false
	if debug_log:
		print("[CassettePlayer:%s] try_interact by %s | asp=%s playing=%s inserted_tape=%s loaded_stream=%s" % [name, str(player), str(_asp != null), str(_asp and _asp.playing), str(_inserted_tape != null), str(_loaded_stream != null)])
	# If a tape/stream is already inserted, eject on interact
	if _inserted_tape != null or _loaded_stream != null:
		if _asp and _asp.playing:
			_asp.stop()
			if debug_log: print("[CassettePlayer] Stopped before eject.")
		_restore_bg_music()
		if eject_on_second_interact:
			_eject_tape_to_player(player)
			# Clear state so the player can insert again later
			_inserted_tape = null
			_loaded_stream = null
			if _asp:
				_asp.stream = null
		_last_interact_ms = now_ms
		return true
	# Otherwise, see if player is holding a CassetteTape
	var tape := _get_held_tape(player)
	if tape == null:
		if debug_log:
			var held: Variant = null
			if player and player.has_method("get_carried_item"): held = player.get_carried_item()
			print("[CassettePlayer] No tape held. carried_item=%s" % [str(held)])
		return false
	# Optional: require human to be aiming at this
	if require_human_crosshair and not _is_crosshair_on_self(player):
		if debug_log: print("[CassettePlayer] Crosshair not on cassette player.")
		return false
	# Insert tape and start playing its track
	if not _load_tape_stream_into_player(tape):
		if debug_log: push_warning("Cassette tape has no valid stream set.")
		return false
	# Set up player and remember stream
	_loaded_stream = _resolve_tape_stream(tape)
	_inserted_tape = null if consume_tape_after_insert else tape
	if _asp:
		_asp.stop()
		_asp.stream = _loaded_stream
		if debug_log: print("[CassettePlayer] AudioStreamPlayer3D stream set. Starting playback...")
		_fade_out_bg_music()
		_asp.play()
	# Consume (remove) the physical tape so it disappears
	if consume_tape_after_insert:
		# Pack a snapshot so we can recreate on eject
		_consumed_tape_packed = _pack_tape_for_return(tape)
		if player and player.has_method("get_carried_item") and player.get_carried_item() == tape and player.has_method("clear_carried_item"):
			player.clear_carried_item()
		if is_instance_valid(tape):
			tape.queue_free()
	if debug_log: print("[CassettePlayer] Inserted '%s' and started playback. Consumed=%s" % [tape.name, str(consume_tape_after_insert)])
	# On success, remember time to avoid immediate duplicate
	_last_interact_ms = now_ms
	return true

func _pack_tape_for_return(tape: Node) -> PackedScene:
	var ps := PackedScene.new()
	var err := ps.pack(tape)
	if debug_log:
		print("[CassettePlayer] Packed tape snapshot result err=", err)
	# In Godot, OK == 0. Only treat non-OK as failure.
	if err != OK:
		if debug_log: push_warning("[CassettePlayer] Failed to pack tape for return; will not be able to eject consumed tape. err=" + str(err))
		return null
	return ps

func _eject_tape_to_player(player: Node) -> void:
	var tape_to_give: Node3D = null
	# If we still have a physical tape reference, use it
	if _inserted_tape != null and is_instance_valid(_inserted_tape) and _inserted_tape is Node3D:
		tape_to_give = _inserted_tape
		# Detach from this player and ensure it's under the scene root
		var wt := (tape_to_give as Node3D).global_transform
		var root := get_tree().current_scene
		if tape_to_give.get_parent() != root and root:
			(tape_to_give.get_parent() as Node).remove_child(tape_to_give)
			root.add_child(tape_to_give)
		(tape_to_give as Node3D).global_transform = wt
	elif _consumed_tape_packed != null:
		var inst := _consumed_tape_packed.instantiate()
		if inst is Node3D:
			tape_to_give = inst
			# Add to world under scene root
			get_tree().current_scene.add_child(tape_to_give)
	else:
		if debug_log: print("[CassettePlayer] No tape snapshot available to eject.")
		return
	# Prefer handing directly to the human if possible
	var handed := false
	if eject_into_player_hand and player and player.has_method("get_carried_item") and player.get_carried_item() == null:
		if player.has_method("_pick_up_item_generic"):
			player.call("_pick_up_item_generic", tape_to_give)
			handed = true
			if debug_log: print("[CassettePlayer] Ejected tape into player's hand.")
	# Otherwise, drop near the player using the standard drop logic (uniform 0.2 scale)
	if not handed and tape_to_give is Node3D:
		var drop_pos := Vector3.ZERO
		var forward := Vector3.FORWARD
		if player is Node3D:
			forward = - (player as Node3D).global_transform.basis.z
			drop_pos = (player as Node3D).global_transform.origin + forward.normalized() * eject_drop_forward + Vector3.UP * eject_drop_up
		else:
			drop_pos = global_transform.origin + Vector3.UP * eject_drop_up
		(tape_to_give as Node3D).global_position = drop_pos
		 # If item exposes on_dropped, use it to ensure physics and 0.2 scale
		if (tape_to_give as Node).has_method("on_dropped"):
			(tape_to_give as Node).call("on_dropped", player, false)
			if debug_log: print("[CassettePlayer] Ejected tape dropped via on_dropped at %s" % [str(drop_pos)])
		else:
			# Fallback: force the unified 0.2 scale and unfreeze physics if present
			(tape_to_give as Node3D).scale = Vector3(0.2, 0.2, 0.2)
			var rb := (tape_to_give as Node3D).get_node_or_null("RigidBody3D") as RigidBody3D
			if rb:
				rb.freeze = false
				rb.sleeping = false
			if debug_log: print("[CassettePlayer] Ejected tape dropped near player at %s with fallback scale 0.2" % [str(drop_pos)])
	# Clear snapshot after successful eject to avoid duplicates
	_consumed_tape_packed = null

func _get_held_tape(player: Node) -> Node:
	var item: Node = null
	if player and player.has_method("get_carried_item"):
		item = player.get_carried_item()
	if item == null:
		return null
	# Accept if item_type == "tape" or it has get_tape_stream
	var type_ok := false
	if item.has_method("get_item_type"):
		type_ok = str(item.get_item_type()) == "tape"
	elif "item_type" in item:
		type_ok = str(item.item_type) == "tape"
	if debug_log:
		print("[CassettePlayer] Held item: name=%s type_ok=%s has_get_tape_stream=%s" % [item.name if "name" in item else str(item), str(type_ok), str(item.has_method("get_tape_stream"))])
	if not type_ok and not item.has_method("get_tape_stream"):
		return null
	return item

func _is_crosshair_on_self(player: Node) -> bool:
	var cam := _get_player_camera(player)
	if cam == null:
		if debug_log: print("[CassettePlayer] No camera found on player for crosshair ray.")
		return false
	var vp := cam.get_viewport()
	if vp == null:
		if debug_log: print("[CassettePlayer] No viewport for camera.")
		return false
	var center: Vector2 = vp.get_visible_rect().size * 0.5
	var origin: Vector3 = cam.project_ray_origin(center)
	var dir: Vector3 = cam.project_ray_normal(center)
	var to: Vector3 = origin + dir * aim_max_distance
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, to)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.exclude = [player]
	var res := space.intersect_ray(params)
	if res.is_empty():
		if debug_log: print("[CassettePlayer] Crosshair ray missed.")
		return false
	var collider: Node = res.get("collider") as Node
	if collider == null:
		if debug_log: print("[CassettePlayer] Crosshair ray had no collider node.")
		return false
	# Consider any child in our subtree a valid hit
	var ok := self == collider or self.is_ancestor_of(collider)
	if not ok:
		# Walk up to 6 parents to find if it belongs to us (covers complex instanced scenes)
		var n := collider
		var d := 0
		while n and d < 6 and not ok:
			if n == self:
				ok = true
				break
			n = n.get_parent(); d += 1
	if debug_log:
		print("[CassettePlayer] Crosshair hit %s | on_self=%s" % [str(collider), str(ok)])
	return ok

func _get_player_camera(player: Node) -> Camera3D:
	if "camera_3d" in player and player.camera_3d is Camera3D:
		return player.camera_3d
	if "_cam" in player and player._cam is Camera3D:
		return player._cam
	var direct := player.get_node_or_null("Camera3D") as Camera3D
	if direct is Camera3D:
		return direct
	# search up to a few levels
	var n := player
	var depth := 0
	while n and depth < 5:
		for c in n.get_children():
			if c is Camera3D:
				return c
		n = n.get_parent(); depth += 1
	return null

func _fade_out_bg_music() -> void:
	var music := get_node_or_null("/root/BgMusic") as AudioStreamPlayer
	if music and music.has_method("fade_out_music"):
		if debug_log: print("[CassettePlayer] Fading out BgMusic...")
		music.call("fade_out_music", bg_music_fade_out_sec)

func _restore_bg_music() -> void:
	var music := get_node_or_null("/root/BgMusic") as AudioStreamPlayer
	if music and not music.playing and music.has_method("ensure_playing"):
		if debug_log: print("[CassettePlayer] Restoring BgMusic if stopped...")
		music.call("ensure_playing")

func _resolve_tape_stream(tape: Node) -> AudioStream:
	if tape == null:
		return null
	if tape.has_method("get_current_stream"):
		var s: AudioStream = tape.get_current_stream()
		if s:
			return s
	if tape.has_method("get_tape_stream"):
		var s2: AudioStream = tape.get_tape_stream()
		if s2:
			return s2
	if "tape_stream" in tape and tape.tape_stream != null:
		return tape.tape_stream
	if "stream" in tape and tape.stream != null:
		return tape.stream
	return null

func _load_tape_stream_into_player(tape: Node) -> bool:
	var s := _resolve_tape_stream(tape)
	if s == null:
		return false
	var p := _get_audio_node()
	if p == null or not is_instance_valid(p):
		if Engine.is_editor_hint():
			print("[CassettePlayer] Audio player node not found; set audio_player_path on ", name)
		return false
	if p is AudioStreamPlayer:
		(p as AudioStreamPlayer).stream = s
	elif p is AudioStreamPlayer3D:
		(p as AudioStreamPlayer3D).stream = s
	return true

func _get_audio_node() -> Node:
	if _audio_node != null and is_instance_valid(_audio_node):
		return _audio_node
	if audio_player_path != NodePath(""):
		_audio_node = get_node_or_null(audio_player_path)
	if _audio_node == null:
		_audio_node = get_node_or_null("AudioStreamPlayer")
	if _audio_node == null:
		_audio_node = get_node_or_null("AudioStreamPlayer3D")
	if _audio_node == null:
		for c in get_children():
			if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
				_audio_node = c
				break
	return _audio_node
