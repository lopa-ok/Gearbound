extends Control

signal closed

@export var tasks: Array[String] = [
	"Find Crowbar",
	"Find White Key",
	"Unlock White lock",
	"Find Blue Key",
	"Find Orange Key",
	"Unlock Orange Lock",
	"Find Red Key",
	"Check the Keypad out",
	"Figure out how to unlock it",
	"Unlock Main door!"
	
]

# Whether clicking the label should toggle the associated checkbox
@export var label_toggles_checkbox: bool = true

var _transparent_icon_tex: Texture2D
var _story_shown: bool = false
const STORY_CFG_PATH := "user://ui_prefs.cfg"
const STORY_SECTION := "checklist_menu"
const STORY_KEY := "intro_seen"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Ensure controller actions exist
	if Engine.is_editor_hint() == false:
		var cs := get_node_or_null("/root/ControllerSupport")
		# Call static if available; fallback to autoload if set up
		if ControllerSupport != null:
			ControllerSupport.ensure_input_map()
	# Ensure menu music is playing in the checklist
	var music := get_node_or_null("/root/BgMusic") as AudioStreamPlayer
	if music and music.has_method("ensure_playing"):
		music.call("ensure_playing")
	# Show story overlay only once per game (session) using root metadata
	var overlay := get_node_or_null("StoryOverlay") as Control
	var root := get_tree().root
	var seen_session := root.has_meta("checklist_prologue_shown") and bool(root.get_meta("checklist_prologue_shown"))
	if overlay:
		if not seen_session:
			# First time this session: show and mark shown so it won’t reappear on reopen
			overlay.visible = true
			_story_shown = true
			_set_base_ui_visible(false)
			root.set_meta("checklist_prologue_shown", true)
			if has_node("%StoryContinue"):
				var btn: Button = %StoryContinue
				if btn and not btn.pressed.is_connected(_on_story_continue):
					btn.pressed.connect(_on_story_continue)
				btn.grab_focus()
		else:
			# Already shown this session: proceed directly to checklist UI
			overlay.visible = false
			_story_shown = false
			_set_base_ui_visible(true)
	# Make intro text larger
	var story_text := get_node_or_null("StoryOverlay/PanelContainer/RootMargin/RootVBox/StoryText") as RichTextLabel
	if story_text:
		story_text.add_theme_font_size_override("normal_font_size", 40)
	_refresh_list()
	%Back.pressed.connect(_on_close)
	# Default focus only when the base UI is visible
	if not _story_shown:
		grab_default_focus()
		# Build focus graph after population
		_ensure_focus_nav()

func _set_base_ui_visible(v: bool) -> void:
	var dim := get_node_or_null("Dim") as CanvasItem
	var panel := get_node_or_null("PanelContainer") as CanvasItem
	if dim:
		dim.visible = v
	if panel:
		panel.visible = v

func _unhandled_input(event: InputEvent) -> void:
	# Story overlay: accept/cancel advances
	if _story_shown:
		if (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")):
			_dismiss_story(false)
			accept_event()
			return
		# Mouse/keyboard fallback
		if event is InputEventMouseButton and event.pressed:
			_dismiss_story(false)
			accept_event()
			return
		elif event is InputEventKey and event.pressed:
			_dismiss_story(false)
			accept_event()
			return
	# Checklist navigation
	if event.is_action_pressed("ui_cancel"):
		_on_close()
		accept_event()
		return
	# Page up/down with shoulders
	if event.is_action_pressed("ui_page_up"):
		_scroll_page(-1)
		accept_event()
	elif event.is_action_pressed("ui_page_down"):
		_scroll_page(1)
		accept_event()

func _on_story_continue() -> void:
	_dismiss_story(true)
	# Ensure music keeps playing after intro
	var music := get_node_or_null("/root/BgMusic") as AudioStreamPlayer
	if music and music.has_method("ensure_playing"):
		music.call("ensure_playing")

func _dismiss_story(_save_seen: bool) -> void:
	var overlay := get_node_or_null("StoryOverlay") as Control
	if overlay:
		overlay.visible = false
	_story_shown = false
	_set_base_ui_visible(true)
	# Give focus to the base UI now that it’s visible
	await get_tree().process_frame
	grab_default_focus()
	_ensure_focus_nav()
	# Per-session gating already handled via root metadata

func _load_story_seen() -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(STORY_CFG_PATH)
	if err != OK:
		return false
	return bool(cfg.get_value(STORY_SECTION, STORY_KEY, false))

func _save_story_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(STORY_CFG_PATH) # okay if missing; creates new on save
	cfg.set_value(STORY_SECTION, STORY_KEY, true)
	cfg.save(STORY_CFG_PATH)

func _on_close():
	emit_signal("closed")
	queue_free()

func grab_default_focus():
	# Prefer Back by default; player can D‑pad down into list
	%Back.grab_focus()

func set_tasks(new_tasks: Array[String]) -> void:
	tasks = new_tasks
	_refresh_list()
	_ensure_focus_nav()

func _refresh_list():
	if not is_inside_tree():
		return
	var list := %List
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	for i in tasks.size():
		var task := tasks[i]
		# Row container without background/border (no box around text)
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.custom_minimum_size = Vector2(0, 48)
		panel.add_theme_stylebox_override("panel", _transparent_panel())
		# Content container
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		panel.add_child(margin)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		margin.add_child(hb)
		# Checkbox visible (no background style)
		var cb := CheckBox.new()
		cb.text = ""
		cb.focus_mode = Control.FOCUS_ALL
		cb.custom_minimum_size = Vector2(28, 28)
		cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_style_checkbox_no_bg(cb)
		# Ensure scroller follows focus
		cb.focus_entered.connect(func(): _ensure_visible_on_focus(cb))
		hb.add_child(cb)
		# Label text only
		var lbl := Label.new()
		lbl.text = str(task)
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		if label_toggles_checkbox:
			lbl.mouse_filter = Control.MOUSE_FILTER_STOP
			lbl.gui_input.connect(Callable(self, "_on_label_gui_input").bind(lbl, cb))
		hb.add_child(lbl)
		# Update visuals on toggle
		cb.toggled.connect(Callable(self, "_on_task_toggled").bind(lbl))
		_apply_task_state(cb.button_pressed, lbl)
		list.add_child(panel)

func _ensure_focus_nav() -> void:
	var back := %Back as Button
	var list := %List as VBoxContainer
	if back == null or list == null:
		return
	var cbs: Array = []
	# Find all CheckBox descendants created in rows
	for n in list.get_children():
		var found := n.find_children("", "CheckBox", true, false)
		for f in found:
			if f is CheckBox:
				cbs.append(f)
	# Wire neighbors
	if cbs.size() > 0:
		back.focus_neighbor_bottom = back.get_path_to(cbs[0])
		for i in cbs.size():
			var cb: CheckBox = cbs[i]
			var up: Control = back if i == 0 else cbs[i - 1]
			var down: Control = back if i == cbs.size() - 1 else cbs[i + 1]
			cb.focus_neighbor_top = cb.get_path_to(up)
			cb.focus_neighbor_bottom = cb.get_path_to(down)
			# Horizontal neighbors stay within the row
			cb.focus_neighbor_left = NodePath("")
			cb.focus_neighbor_right = NodePath("")

func _scroll_page(dir: int) -> void:
	var scroll := get_node_or_null("PanelContainer/RootMargin/RootVBox/Scroll") as ScrollContainer
	if scroll == null:
		return
	var amount := int(scroll.get_rect().size.y * 0.9)
	scroll.scroll_vertical = max(0, scroll.scroll_vertical + amount * dir)

func _ensure_visible_on_focus(ctrl: Control) -> void:
	var scroll := get_node_or_null("PanelContainer/RootMargin/RootVBox/Scroll") as ScrollContainer
	if scroll:
		scroll.ensure_control_visible(ctrl)

func _transparent_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(0)
	return sb

func _transparent_icon() -> Texture2D:
	if _transparent_icon_tex:
		return _transparent_icon_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	_transparent_icon_tex = ImageTexture.create_from_image(img)
	return _transparent_icon_tex

func _on_task_toggled(checked: bool, lbl: Label) -> void:
	_apply_task_state(checked, lbl)

func _apply_task_state(checked: bool, lbl: Label) -> void:
	# Dim label when completed
	var m := lbl.modulate
	m.a = 0.6 if checked else 1.0
	lbl.modulate = m

func _on_label_gui_input(event: InputEvent, _label: Control, cb: CheckBox) -> void:
	if not label_toggles_checkbox:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		cb.button_pressed = not cb.button_pressed

func _on_row_mouse_enter(panel: PanelContainer, sb: StyleBox) -> void:
	panel.add_theme_stylebox_override("panel", sb)

func _on_row_mouse_exit(panel: PanelContainer, sb: StyleBox) -> void:
	panel.add_theme_stylebox_override("panel", sb)

func _make_panel_style(col: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	sb.corner_radius_bottom_left = 8
	return sb

func _make_checkbox_style(col: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	sb.set_content_margin_all(6)
	return sb

func _style_checkbox_minimal(cb: CheckBox) -> void:
	# Fully transparent background and icons to remove any box visuals
	var t := _transparent_panel()
	cb.add_theme_stylebox_override("normal", t)
	cb.add_theme_stylebox_override("hover", t)
	cb.add_theme_stylebox_override("pressed", t)
	cb.add_theme_stylebox_override("disabled", t)
	var icon := _transparent_icon()
	cb.add_theme_icon_override("checked", icon)
	cb.add_theme_icon_override("unchecked", icon)
	cb.add_theme_icon_override("radio_checked", icon)
	cb.add_theme_icon_override("radio_unchecked", icon)
	cb.add_theme_constant_override("h_separation", 0)
	cb.add_theme_constant_override("check_v_offset", 0)

func _style_checkbox_no_bg(cb: CheckBox) -> void:
	# Remove background/border but keep default icons so the checkbox shows
	var t := _transparent_panel()
	cb.add_theme_stylebox_override("normal", t)
	cb.add_theme_stylebox_override("hover", t)
	cb.add_theme_stylebox_override("pressed", t)
	cb.add_theme_stylebox_override("disabled", t)
	cb.add_theme_constant_override("h_separation", 8)
	cb.add_theme_constant_override("check_v_offset", 0)
