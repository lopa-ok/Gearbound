extends Node3D

@export var anim_player_path: NodePath = NodePath("AnimationPlayer")
@export var open_anim: StringName = &"open"
@export var allow_interrupt: bool = true

var _ap: AnimationPlayer
var _is_open: bool = false
var _busy: bool = false

func _ready() -> void:
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	set_process(false)
	set_physics_process(false)
	if _ap:
		_ap.animation_finished.connect(_on_anim_finished)
		print("[ToggleOpenAnimation] Ready on %s | AP='%s' | has 'open'=%s | length=%s" % [get_path(), _ap.name, _ap.has_animation(open_anim), (_ap.get_animation(open_anim).length if _ap.has_animation(open_anim) else -1)])
	else:
		push_warning("[ToggleOpenAnimation] AnimationPlayer not found at path: %s" % [anim_player_path])

func try_interact(_user: Node) -> bool:
	print("[ToggleOpenAnimation] try_interact on %s by %s | busy=%s allow_interrupt=%s" % [get_path(), _user, _busy, allow_interrupt])
	if _ap == null:
		push_warning("[ToggleOpenAnimation] No AnimationPlayer. Set 'anim_player_path' correctly.")
		return false
	if _busy and not allow_interrupt:
		print("[ToggleOpenAnimation] Ignored: busy and interrupts disabled")
		return false
	if not _ap.has_animation(open_anim):
		push_warning("[ToggleOpenAnimation] Missing 'open' animation on AnimationPlayer '%s'" % _ap.name)
		return false
	_toggle()
	return true

func get_interact_label() -> String:
	if _is_open:
		return "Close"
	return "Open"

func _toggle() -> void:
	if _ap == null:
		return
	_busy = true
	# Safely determine current animation info without touching position/length unless playing
	var open_len := -1.0
	if _ap.has_animation(open_anim):
		open_len = _ap.get_animation(open_anim).length
	var pos := 0.0
	var anim_len := open_len
	var current_name := String(_ap.current_animation)
	if _ap.is_playing():
		pos = _ap.current_animation_position
		anim_len = _ap.current_animation_length
	if _is_open:
		print("[ToggleOpenAnimation] Closing | current='%s' pos=%.3f len=%.3f" % [current_name, pos, anim_len])
		# Closing: play the 'open' animation backwards
		if current_name == String(open_anim) and allow_interrupt and _ap.is_playing():
			var t := anim_len - pos
			print("[ToggleOpenAnimation] Interrupt close: play_backwards(open) from t=%.3f" % t)
			_ap.play_backwards(open_anim)
			_ap.seek(t, true)
		else:
			print("[ToggleOpenAnimation] Close: play_backwards(open) from end")
			_ap.play_backwards(open_anim)
	else:
		print("[ToggleOpenAnimation] Opening | current='%s' pos=%.3f len=%.3f" % [current_name, pos, anim_len])
		# Opening: play the 'open' animation forward
		if current_name == String(open_anim) and allow_interrupt and _ap.is_playing():
			var t := pos
			print("[ToggleOpenAnimation] Interrupt open: play(open) from t=%.3f" % t)
			_ap.play(open_anim)
			_ap.seek(t, true)
		else:
			print("[ToggleOpenAnimation] Open: play(open) from start")
			_ap.play(open_anim)

func _on_anim_finished(anim_name: StringName) -> void:
	print("[ToggleOpenAnimation] Animation finished: '%s' | toggling state" % anim_name)
	if anim_name == open_anim:
		_is_open = not _is_open
		print("[ToggleOpenAnimation] Now is_open=%s" % _is_open)
	_busy = false
