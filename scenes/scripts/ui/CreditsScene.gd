# filepath: /Users/lopa/test/scenes/scripts/ui/CreditsScene.gd
extends Control

@export_multiline var story_text: String = "[center][b]After countless rooms and locked doors...[/b]\nYou pieced together scattered clues,\ncracked the keypad, and found the way out.\n\nBut the house never wanted to trap you—\nit wanted to teach you how to look.\nEvery scrape on a hinge was a compass.\nEvery shadow on a shelf was a number waiting to be read.\nYou learned to stand still, to listen to the hum behind the walls,\nto count the beats of flickering lights,\nto measure the distance between silence and sound.\n\nYou pushed on when a puzzle mocked you,\nrewrote plans when a door refused to budge,\nand laughed at your own notes when a simple answer had been there all along.\n\nYou learned to carry less and notice more.\nThat the fastest route is often the one taken slowly, on purpose.\nThat curiosity is a key that never wears out.\n\nPast the final lock, you felt the room breathe with you:\npanels settling, circuits cooling, the space letting go.\nYou didn’t just exit—\nyou graduated from the maze.\n\n[b]Well done.[/b]\nTake this momentum with you.\nThere are more rooms in the world than walls.\n[/center]\n"
@export_multiline var credits_text: String = "[center][b]Move faster[/b]\n\nDesign & Code: Lopa\n3D Assets: Youssef Hany + Various Authors\nMusic: Lopa\nSFX: Cisco\nMade for Shiba arcade\n\nThank you for playing!\n— Lopa[/center]\n"
@export var allow_close: bool = false
@export var return_scene_path: String = "res://scenes/MainMenu.tscn"
@export var base_font_size: int = 40

@export var auto_scroll: bool = true
@export var pixels_per_second: float = 30.0  # slower default
@export var fast_multiplier: float = 3.0     # speed-up factor while holding Space
@export var start_delay_sec: float = 0.5
@export var end_hold_sec: float = 1.0
@export var fade_in_sec: float = 0.8
@export var fade_out_sec: float = 0.8

@export var return_to_menu_on_end: bool = false
@export var quit_on_end: bool = false
@export var show_quit_button_at_end: bool = true
# New: credits music controls
@export var credits_music: AudioStream
@export var credits_music_volume_db: float = -6.0
@export var credits_music_fade_in_sec: float = 1.2
@export var bg_music_fade_out_sec: float = 1.2

var _closing: bool = false
var _scrolling: bool = false
var _fast: bool = false
var _content_h: float = 0.0
var _view_h: float = 0.0
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _credits_player: AudioStreamPlayer = null
@onready var _mask: Control = get_node_or_null("Mask")
@onready var _label: RichTextLabel = get_node_or_null("Mask/CreditsText")
@onready var _quit_btn: Button = get_node_or_null("QuitButton")

func _ready() -> void:
	# Prevent pausing while credits are active
	add_to_group("no_pause")
	# Ensure mouse is not locked during credits
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Play transition-in when the credits scene loads
	Transition.play_transition("transition_in")
	# Start audio: fade out BG music and fade in credits music (if provided)
	_start_credits_music()
	if _label:
		_label.bbcode_enabled = true
		_label.text = ""
		_label.clear()
		# Wrap all content in a larger font size
		var combined := "[font_size=%d]%s\n\n%s[/font_size]" % [base_font_size, story_text, credits_text]
		_label.append_text(combined)
		_label.fit_content = true
		_label.scroll_active = false
	# Prepare quit button if present
	if _quit_btn:
		_quit_btn.visible = false
		_quit_btn.modulate.a = 0.0
		_quit_btn.pressed.connect(_on_quit_button_pressed)
		 # Center and style big button
		_layout_quit_button()
		_apply_quit_button_style()
		# Relayout on window resize
		if has_signal("resized"):
			resized.connect(_on_resized)
	modulate.a = 0.0
	grab_focus()
	_run_sequence()

func _run_sequence() -> void:
	# Ensure layout is settled and set start position BEFORE fade-in
	await get_tree().process_frame
	await get_tree().process_frame
	if _mask and _label:
		_label.size.x = _mask.size.x
		_label.fit_content = true
		await get_tree().process_frame
		_view_h = float(_mask.size.y)
		# Place the label just below the viewport so it's not visible during fade-in
		_label.position = Vector2(0, _view_h + 1.0)
	# Now fade in
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, fade_in_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished
	if start_delay_sec > 0:
		await get_tree().create_timer(start_delay_sec).timeout
	if not auto_scroll:
		return
	# Recalculate sizes to get accurate content height for the scroll
	await get_tree().process_frame
	_content_h = float(_label.get_content_height())
	# Begin per-frame scrolling so we can change speed dynamically
	_scrolling = true
	set_process(true)

func _process(delta: float) -> void:
	if not _scrolling or _closing:
		return
	var speed := pixels_per_second * (fast_multiplier if _fast else 1.0)
	_label.position.y -= speed * delta
	if _label.position.y <= -_content_h:
		_scrolling = false
		set_process(false)
		# Optional hold before showing button or exiting
		if end_hold_sec > 0:
			await get_tree().create_timer(end_hold_sec).timeout
		if show_quit_button_at_end and _quit_btn:
			await _show_quit_button()
		else:
			await _fade_and_exit()

func _show_quit_button() -> void:
	# Ensure layout/style before showing, in case resolution changed mid-credits
	_layout_quit_button()
	_apply_quit_button_style()
	_quit_btn.visible = true
	_quit_btn.grab_focus()
	var t := create_tween()
	t.tween_property(_quit_btn, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished

func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	# Handle speed-up on Space (press = faster, release = back to normal)
	if event is InputEventKey and event.keycode == KEY_SPACE:
		_fast = event.pressed
		return
	# Ignore Esc and mouse clicks to avoid accidental exits
	# If early close is explicitly allowed, only allow Enter to act
	if not allow_close:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		if _quit_btn and _quit_btn.visible:
			await _on_quit_button_pressed()
		else:
			await _fade_and_exit()

func _fade_and_exit() -> void:
	if _closing:
		return
	_closing = true
	# Fade out credits music while fading screen
	_stop_credits_music(min(0.8, fade_out_sec))
	var t3 := create_tween()
	t3.tween_property(self, "modulate:a", 0.0, fade_out_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t3.finished
	# Restore previous mouse mode before switching scenes or quitting
	Input.mouse_mode = _prev_mouse_mode
	_change_scene_or_quit()

func _on_quit_button_pressed() -> void:
	if _closing:
		return
	_closing = true
	# Begin fading out credits music alongside the transition
	_stop_credits_music(0.8)
	await Transition.play_transition("transition_out")
	Input.mouse_mode = _prev_mouse_mode
	get_tree().quit()

func _change_scene_or_quit() -> void:
	if return_to_menu_on_end and return_scene_path != "":
		# Fade out credits music during transition to next scene
		_stop_credits_music(0.8)
		await Transition.play_transition("transition_out")
		Input.mouse_mode = _prev_mouse_mode
		get_tree().change_scene_to_file(return_scene_path)
	elif quit_on_end:
		_stop_credits_music(0.8)
		await Transition.play_transition("transition_out")
		Input.mouse_mode = _prev_mouse_mode
		get_tree().quit()
	else:
		# Hold on this scene
		set_process(false)
		set_physics_process(false)

func _start_credits_music() -> void:
	# Fade out global BG music if present
	var music := get_node_or_null("/root/BgMusic")
	if music and music.has_method("fade_out_music"):
		music.call("fade_out_music", bg_music_fade_out_sec)
	# Play local credits music
	if credits_music == null:
		return
	if _credits_player == null:
		_credits_player = AudioStreamPlayer.new()
		_credits_player.name = "CreditsMusic"
		_credits_player.bus = &"Music"
		add_child(_credits_player)
	_credits_player.stream = credits_music
	_credits_player.volume_db = -60.0
	_credits_player.play()
	var t := create_tween()
	t.tween_property(_credits_player, "volume_db", credits_music_volume_db, max(0.0, credits_music_fade_in_sec))

func _stop_credits_music(fade_sec: float = 0.8) -> void:
	if _credits_player == null:
		return
	var t := create_tween()
	t.tween_property(_credits_player, "volume_db", -80.0, max(0.0, fade_sec))
	t.tween_callback(Callable(_credits_player, "stop"))

func _layout_quit_button() -> void:
	if _quit_btn == null:
		return
	# Use top-left anchors and absolute positioning
	_quit_btn.anchor_left = 0.0
	_quit_btn.anchor_top = 0.0
	_quit_btn.anchor_right = 0.0
	_quit_btn.anchor_bottom = 0.0
	# Responsive size
	var vp := get_viewport_rect().size
	var w := clampi(int(vp.x * 0.4), 420, 900)
	var h := clampi(int(max(80.0, vp.y * 0.10)), 80, 220)
	_quit_btn.custom_minimum_size = Vector2(w, h)
	_quit_btn.size = Vector2(w, h)
	# Center within the viewport
	_quit_btn.position = (vp - _quit_btn.size) * 0.5
	_quit_btn.z_index = 50

func _apply_quit_button_style() -> void:
	if _quit_btn == null:
		return
	# Big, readable font; scale with height with sane floor/ceiling
	var vp_h := get_viewport_rect().size.y
	var fs := clampi(int(max(base_font_size * 1.25, vp_h / 18.0)), 28, 72)
	_quit_btn.add_theme_font_size_override("font_size", fs)
	# Extra padding for a chunky look
	_quit_btn.add_theme_constant_override("hseparation", 16)
	_quit_btn.add_theme_constant_override("vseparation", 10)

func _on_resized() -> void:
	_layout_quit_button()
	_apply_quit_button_style()
