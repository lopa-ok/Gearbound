extends CanvasLayer

@export var color: Color = Color(0, 0, 0, 1)
@export var duration_out: float = 0.12
@export var duration_in: float = 0.18

var _rect: ColorRect
var _tween: Tween

func _ready() -> void:
	layer = 100
	_rect = ColorRect.new()
	_rect.color = color
	_rect.modulate = Color(1, 1, 1, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)

func play_switch(col: Color = color, fade_out: float = duration_out, fade_in: float = duration_in) -> void:
	if _rect == null:
		return
	_rect.color = col
	_rect.visible = true
	_rect.modulate = Color(1, 1, 1, 0)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_rect, "modulate", Color(1, 1, 1, 1), max(0.01, fade_out))
	_tween.tween_property(_rect, "modulate", Color(1, 1, 1, 0), max(0.01, fade_in))
	_tween.finished.connect(func():
		if is_instance_valid(_rect):
			_rect.visible = false
	)
