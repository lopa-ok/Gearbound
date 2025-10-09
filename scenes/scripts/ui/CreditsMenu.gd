# filepath: /Users/lopa/test/scenes/scripts/ui/CreditsMenu.gd
extends Control

signal close_requested

@export var credits_lines: Array[String] = [
	"Move faster",
	"",
	"Design & Code: Your Name",
	"3D Assets: Various Authors",
	"Music: ...",
	"SFX: ...",
	"Special Thanks: ...",
	"",
	"Thank you for playing!",
	"",
	"—",
]

func _ready() -> void:
	_populate()

func open() -> void:
	visible = true
	grab_focus()

func close() -> void:
	visible = false
	emit_signal("close_requested")

func _populate() -> void:
	var text := get_node_or_null("CreditsText") as RichTextLabel
	if text == null:
		return
	# Compose a long text block for scrolling
	var s := ""
	for line in credits_lines:
		s += line + "\n"
	# Repeat to ensure scrollable length
	for i in 10:
		s += "\n"
		s += "Thanks for playing!\n"
		s += "— The Team\n"
	text.text = s
	text.scroll_to_line(0)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
		close()
	elif event is InputEventMouseButton and event.pressed:
		close()
