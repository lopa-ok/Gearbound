# filepath: /Users/lopa/test/scenes/scripts/interactables/ToggleOpenAudio.gd
extends Node3D

## Toggle-style interactor that plays "open" and "close" sounds instead of animations.
## Mirrors the API of ToggleOpenAnimation so it plugs into your existing interact flow.

@export var open_player_path: NodePath = NodePath("OpenSFX")
@export var close_player_path: NodePath = NodePath("CloseSFX")
@export var allow_interrupt: bool = true
# When true, state flips after the SFX finishes; otherwise it flips immediately on start
@export var toggle_on_finished: bool = true

var _open_player: Node
var _close_player: Node
var _is_open: bool = false
var _busy: bool = false
var _pending_open: bool = false

func _ready() -> void:
	_open_player = _get_player(open_player_path)
	_close_player = _get_player(close_player_path)
	_connect_finished(_open_player)
	_connect_finished(_close_player)
	print("[ToggleOpenAudio] Ready on %s | open=%s close=%s" % [get_path(), _open_player, _close_player])

func try_interact(_user: Node) -> bool:
	print("[ToggleOpenAudio] try_interact on %s by %s | busy=%s allow_interrupt=%s" % [get_path(), _user, _busy, allow_interrupt])
	if _open_player == null and _close_player == null:
		push_warning("[ToggleOpenAudio] No AudioStreamPlayer nodes set. Assign open_player_path/close_player_path.")
		return false
	if _busy and not allow_interrupt:
		print("[ToggleOpenAudio] Ignored: busy and interrupts disabled")
		return false
	_toggle()
	return true

func get_interact_label() -> String:
	return "Close" if _is_open else "Open"

func _toggle() -> void:
	_busy = true
	var target_open := not _is_open
	_pending_open = target_open
	# Interrupt any current playback if allowed
	if allow_interrupt:
		_stop_player(_open_player)
		_stop_player(_close_player)
	# Choose which SFX to play
	var p := _open_player if target_open else _close_player
	if p:
		_play_player(p)
		if not toggle_on_finished:
			_is_open = target_open
			_busy = false
	else:
		# No player for this action; toggle immediately
		_is_open = target_open
		_busy = false

func _on_sfx_finished() -> void:
	# Called by either player
	if toggle_on_finished:
		_is_open = _pending_open
	_busy = false
	print("[ToggleOpenAudio] Finished | is_open=%s" % _is_open)

func _get_player(path: NodePath) -> Node:
	if String(path).is_empty():
		return null
	var n := get_node_or_null(path)
	if n == null:
		return null
	if not (n is AudioStreamPlayer or n is AudioStreamPlayer3D):
		push_warning("[ToggleOpenAudio] Node at '%s' is not an AudioStreamPlayer(3D)" % [path])
		return null
	return n

func _connect_finished(p: Node) -> void:
	if p == null:
		return
	# Both AudioStreamPlayer and AudioStreamPlayer3D have a 'finished' signal in Godot 4.
	if p.has_signal("finished"):
		p.finished.connect(_on_sfx_finished)

func _play_player(p: Node) -> void:
	if p == null:
		return
	if p.has_method("play"):
		p.play()

func _stop_player(p: Node) -> void:
	if p == null:
		return
	if p.has_method("stop"):
		p.stop()
