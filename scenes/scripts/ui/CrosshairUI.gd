extends Control

@export var color: Color = Color(1, 1, 1, 0.9)
@export var highlight_color: Color = Color(1.0, 0.85, 0.2, 1.0)
@export var base_size: float = 8.0
@export var ring_thickness: float = 2.0
@export var gap: float = 4.0
@export var line_len: float = 5.0
@export var line_thickness: float = 2.0
# New: hint text appearance
@export var hint_text_color: Color = Color(1, 1, 1, 0.96)
@export var hint_bg_color: Color = Color(0, 0, 0, 0.55)
@export var hint_font_size: int = 16
@export var hint_margin: Vector2 = Vector2(8, 6)

var _interactable: bool = false
var _pulse_t: float = 0.0
var _hint_text: String = ""

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

func set_crosshair_visible(v: bool) -> void:
	visible = v

func set_interactable_hint(v: bool) -> void:
	if _interactable != v:
		_interactable = v
		_pulse_t = 0.0
		queue_redraw()

# New: external setter for hint text
func set_hint_text(t: String) -> void:
	if _hint_text != t:
		_hint_text = t
		queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_t += delta
	queue_redraw()

func _draw() -> void:
	if not visible:
		return
	var vp: Vector2 = get_viewport_rect().size
	var center: Vector2 = vp * 0.5
	var col: Color = highlight_color if _interactable else color
	var pulse: float = (0.5 + 0.5 * sin(_pulse_t * 8.0)) if _interactable else 0.0
	var ring_r: float = base_size + pulse * 2.0
	# Ring
	draw_arc(center, ring_r, 0.0, TAU, 32, col, ring_thickness, true)
	# 4 ticks
	var dirs := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	for d in dirs:
		var start: Vector2 = center + d * gap
		var endp: Vector2 = center + d * (gap + line_len)
		draw_line(start, endp, col, line_thickness, true)
	# Hint text below crosshair
	if _hint_text != "":
		var font := ThemeDB.fallback_font
		var font_size_px := hint_font_size
		var text_size := font.get_string_size(_hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_px)
		var box_size := text_size + hint_margin * 2.0
		var box_pos := center + Vector2(-box_size.x * 0.5, ring_r + gap + 10.0)
		# background
		draw_rect(Rect2(box_pos, box_size), hint_bg_color, true)
		# text
		var text_pos := box_pos + hint_margin + Vector2(0, text_size.y * 0.1)
		draw_string(font, text_pos, _hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size_px, hint_text_color)
