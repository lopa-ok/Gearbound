extends Node3D

@export var anim_player_paths: Array[NodePath] = []
@export var open_anim: StringName = &"open"
@export var allow_interrupt: bool = true

var _aps: Array[AnimationPlayer] = []
var _is_open: bool = false
var _busy: bool = false
var _waiting: int = 0

func _ready() -> void:
	_aps.clear()
	for p in anim_player_paths:
		var ap := get_node_or_null(p) as AnimationPlayer
		if ap:
			_aps.append(ap)
			ap.animation_finished.connect(_on_anim_finished)
		else:
			push_warning("[ToggleOpenAnimationGroup] AnimationPlayer not found at path: %s" % [p])
	print("[ToggleOpenAnimationGroup] Ready on %s | players=%d" % [get_path(), _aps.size()])

func try_interact(_user: Node) -> bool:
	print("[ToggleOpenAnimationGroup] try_interact on %s by %s | busy=%s allow_interrupt=%s" % [get_path(), _user, _busy, allow_interrupt])
	if _aps.is_empty():
		push_warning("[ToggleOpenAnimationGroup] No AnimationPlayers set")
		return false
	if _busy and not allow_interrupt:
		print("[ToggleOpenAnimationGroup] Ignored: busy and interrupts disabled")
		return false
	for ap in _aps:
		if ap and not ap.has_animation(open_anim):
			push_warning("[ToggleOpenAnimationGroup] Missing 'open' animation on AnimationPlayer '%s'" % ap.name)
			return false
	_toggle()
	return true

func get_interact_label() -> String:
	if _is_open:
		return "Close"
	return "Open"

func _toggle() -> void:
	if _aps.is_empty():
		return
	_busy = true
	_waiting = 0
	for ap in _aps:
		if ap == null:
			continue
		var current_name := String(ap.current_animation)
		var pos := 0.0
		var anim_len := 0.0
		if ap.has_animation(open_anim):
			anim_len = ap.get_animation(open_anim).length
		if ap.is_playing():
			pos = ap.current_animation_position
			anim_len = ap.current_animation_length
		if _is_open:
			print("[ToggleOpenAnimationGroup] Closing '%s' | current='%s' pos=%.3f len=%.3f" % [ap.name, current_name, pos, anim_len])
			if current_name == String(open_anim) and allow_interrupt and ap.is_playing():
				var t: float = max(0.0, anim_len - pos)
				ap.play_backwards(open_anim)
				ap.seek(t, true)
			else:
				ap.play_backwards(open_anim)
		else:
			print("[ToggleOpenAnimationGroup] Opening '%s' | current='%s' pos=%.3f len=%.3f" % [ap.name, current_name, pos, anim_len])
			if current_name == String(open_anim) and allow_interrupt and ap.is_playing():
				var t2: float = pos
				ap.play(open_anim)
				ap.seek(t2, true)
			else:
				ap.play(open_anim)
		_waiting += 1
	if _waiting == 0:
		_busy = false

func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name != open_anim:
		return
	if _waiting > 0:
		_waiting -= 1
		if _waiting == 0:
			_is_open = not _is_open
			_busy = false
			print("[ToggleOpenAnimationGroup] All animations finished. Now is_open=%s" % _is_open)
