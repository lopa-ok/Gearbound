extends Control

@export var text_color: Color = Color(1, 1, 1, 0.96)
@export var bg_color: Color = Color(0, 0, 0, 0.0)
@export var show_background: bool = false
@export var font_size: int = 22
@export var margin: Vector2 = Vector2(16, 16)
@export_enum("bottom_left", "bottom_right") var corner: String = "bottom_left"
@export var fade_out_time: float = 0.25

var _text: String = ""
var _time_left: float = 0.0
var _alpha: float = 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	visible = true

func show_message(t: String, duration_sec: float = 1.0) -> void:
	_text = t
	_time_left = max(0.0, duration_sec)
	_alpha = 1.0
	queue_redraw()

func clear() -> void:
	_text = ""
	_time_left = 0.0
	_alpha = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if _text == "":
		return
	if _time_left > 0.0:
		_time_left -= delta
		if _time_left <= 0.0:
			_time_left = 0.0
	else:
		# Fade out after time elapses
		if fade_out_time > 0.0:
			_alpha = max(0.0, _alpha - delta / fade_out_time)
			if _alpha == 0.0:
				_text = ""
				queue_redraw()
		else:
			_text = ""
			queue_redraw()
	queue_redraw()

func _draw() -> void:
	if _text == "":
		return
	var font := ThemeDB.fallback_font
	var fs := font_size
	var vp: Vector2 = get_viewport_rect().size
	var text_size := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var box_size := text_size + margin * 2.0
	var box_pos := Vector2.ZERO
	if corner == "bottom_left":
		box_pos = Vector2(margin.x, vp.y - box_size.y - margin.y)
	else:
		box_pos = Vector2(vp.x - box_size.x - margin.x, vp.y - box_size.y - margin.y)
	# background (optional, default off)
	if show_background and bg_color.a > 0.0:
		var bg := Color(bg_color.r, bg_color.g, bg_color.b, bg_color.a * _alpha)
		draw_rect(Rect2(box_pos, box_size), bg, true)
	# subtle shadow for legibility
	var text_pos := box_pos + margin + Vector2(0, text_size.y * 0.1)
	draw_string(font, text_pos + Vector2(1,1), _text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(0,0,0,0.6 * _alpha))
	draw_string(font, text_pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(text_color.r, text_color.g, text_color.b, text_color.a * _alpha))
