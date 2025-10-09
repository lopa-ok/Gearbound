# filepath: /Users/lopa/test/scenes/scripts/ui/HintsMenu.gd
extends Control

signal close_requested

# Flat list compatibility (used if categories is empty)
@export var hints: Array[String] = [
	"Tip: The keypad code is randomized each game (digits 1–6).",
	"Tip: Shelves can spawn a number of items matching the keypad digits.",
	"Tip: Use the keypad to open matching doors after entering the correct code.",
]

# Rich hierarchical categories with subcategories
@export var categories: Dictionary = {
	"Crowbar": [
		"Seems pretty sharp...",
		"Could probably open some vents.",
		"Usually lying around the house.",
	],
	"Keys": [
		"Each color matches a specific lock.",
		"Solve puzzles to find it",
	],
	"Keypad Lock": [
		"The owner seems obsessed with plants...",
		"Maybe check around the house for some greenery?",
	],
}

@export var start_expanded := false
@export var animation_duration := 0.25

@onready var _content: VBoxContainer = get_node_or_null("PanelContainer/RootMargin/RootVBox/Scroll/Content")

func _ready() -> void:
	_ensure_content()
	_populate()
	var back := _get_back_button()
	if back:
		back.pressed.connect(_on_back_pressed)

func _ensure_content() -> void:
	if _content != null:
		return
	var root_vbox := get_node_or_null("PanelContainer/RootMargin/RootVBox") as VBoxContainer
	if root_vbox == null:
		return
	# Remove legacy Tree if present to avoid layout conflicts
	var legacy_tree := root_vbox.get_node_or_null("HintsTree") as Tree
	if legacy_tree:
		legacy_tree.queue_free()
	# Create Scroll + Content
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size.x = 600
	scroll.add_child(content)
	var sep := root_vbox.get_node_or_null("Sep1")
	if sep:
		# Godot 4: use add_sibling to insert after separator
		sep.add_sibling(scroll)
		# Ensure position is directly after separator
		var sep_index := sep.get_index()
		root_vbox.move_child(scroll, sep_index + 1)
	else:
		root_vbox.add_child(scroll)
	_content = content

func connect_signals(back_cb: Callable) -> void:
	var back := _get_back_button()
	if back:
		back.pressed.connect(back_cb)

func grab_default_focus() -> void:
	var back := _get_back_button()
	if back:
		back.grab_focus()

func open() -> void:
	visible = true
	_ensure_content()
	_populate()
	grab_default_focus()

func close() -> void:
	visible = false
	emit_signal("close_requested")

# Backwards compatible setter for flat hints
func set_hints(list: Array[String]) -> void:
	hints = list.duplicate()
	categories.clear()
	_populate()

# New API to set categories tree
func set_categories(data: Dictionary) -> void:
	categories = data.duplicate(true)
	_populate()

func _populate() -> void:
	_ensure_content()
	if _content == null:
		return
	# Clear
	for c in _content.get_children():
		c.queue_free()
	# Decide data source: categories if present else flat hints under "Hints"
	if categories.size() > 0:
		for k in categories.keys():
			_create_section(_content, str(k), categories[k])
	else:
		_create_section(_content, "Hints", hints)

func _create_section(parent: VBoxContainer, title: String, data) -> void:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 8)

	var header := Button.new()
	header.text = title
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.custom_minimum_size.x = 300
	header.focus_mode = Control.FOCUS_ALL
	header.add_theme_font_size_override("font_size", 32)

	var clip := Control.new()
	clip.clip_contents = true
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.custom_minimum_size.y = 0
	clip.modulate.a = 0.0

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_FILL
	body.custom_minimum_size.x = 400
	body.add_theme_constant_override("separation", 6)
	clip.add_child(body)

	# Populate body
	_build_items(body, data)

	# Separator for visual clarity
	var sep := HSeparator.new()

	section.add_child(header)
	section.add_child(clip)
	section.add_child(sep)
	parent.add_child(section)

	# Store refs for toggling
	section.set_meta("clip", clip)
	section.set_meta("body", body)
	section.set_meta("expanded", start_expanded)

	# Precompute target height after layout
	_calculate_section_target_deferred(section)
	header.pressed.connect(func(): _toggle_section(section))

func _calculate_section_target_deferred(section: VBoxContainer) -> void:
	await get_tree().process_frame
	var body: Control = section.get_meta("body")
	var clip: Control = section.get_meta("clip")
	# Temporarily expand to measure content height after layout
	clip.custom_minimum_size.y = 100000.0
	clip.modulate.a = 0.0
	await get_tree().process_frame
	var measured: float = max(body.get_minimum_size().y, body.get_combined_minimum_size().y)
	section.set_meta("target_height", measured)
	var expanded: bool = section.get_meta("expanded")
	clip.custom_minimum_size.y = measured if expanded else 0.0
	clip.modulate.a = 1.0 if expanded else 0.0
	await get_tree().process_frame
	clip.custom_minimum_size.y = measured if expanded else 0.0
	clip.modulate.a = 1.0 if expanded else 0.0

func _toggle_section(section: VBoxContainer) -> void:
	var expanded: bool = section.get_meta("expanded")
	if expanded:
		_collapse_section(section)
	else:
		_expand_section(section)
	section.set_meta("expanded", not expanded)

func _expand_section(section: VBoxContainer, animate: bool = true) -> void:
	var clip: Control = section.get_meta("clip")
	var body: Control = section.get_meta("body")
	var fallback: float = max(body.get_minimum_size().y, body.get_combined_minimum_size().y)
	var target: float = float(section.get_meta("target_height")) if section.has_meta("target_height") else fallback
	if not animate:
		clip.custom_minimum_size.y = target
		clip.modulate.a = 1.0
		return
	var t := create_tween()
	t.tween_property(clip, "custom_minimum_size:y", target, animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(clip, "modulate:a", 1.0, animation_duration * 0.8)

func _collapse_section(section: VBoxContainer, animate: bool = true) -> void:
	var clip: Control = section.get_meta("clip")
	if not animate:
		clip.custom_minimum_size.y = 0
		clip.modulate.a = 0.0
		return
	var t := create_tween()
	t.tween_property(clip, "custom_minimum_size:y", 0.0, animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(clip, "modulate:a", 0.0, animation_duration * 0.8)

func _measure_body(body: Control) -> float:
	return body.get_combined_minimum_size().y

func _build_items(parent: VBoxContainer, data) -> void:
	match typeof(data):
		TYPE_STRING:
			_add_hint_row(parent, str(data))
		TYPE_ARRAY:
			for v in data:
				_build_items(parent, v)
		TYPE_DICTIONARY:
			for k in data.keys():
				_create_section(parent, str(k), data[k])
		_:
			pass

func _add_hint_row(parent: VBoxContainer, text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 32
	row.add_theme_constant_override("separation", 8)
	var bullet := Label.new()
	bullet.text = "•"
	bullet.custom_minimum_size.x = 20
	bullet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bullet.add_theme_font_size_override("font_size", 28)
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size.x = 160
	lbl.add_theme_font_size_override("font_size", 28)
	row.add_child(bullet)
	row.add_child(lbl)
	parent.add_child(row)

func _get_back_button() -> Button:
	var back: Button = get_node_or_null("%Back") as Button
	if back == null:
		back = get_node_or_null("PanelContainer/RootMargin/RootVBox/TopBar/Back") as Button
	return back

func _on_back_pressed() -> void:
	close()
