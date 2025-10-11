extends AudioStreamPlayer

@export var default_volume_db: float = 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Ensure on Music bus
	if str(bus) == "" or String(bus) != "Music":
		bus = &"Music"
	# Mark as background music for auto-detection by MusicManager
	if not is_in_group("bg_music"):
		add_to_group("bg_music")

func ensure_playing():
	# Start or resume background music at the desired volume
	if not playing:
		volume_db = default_volume_db
		play()

func fade_out_music(duration: float = 2.0):
	var tween = create_tween()
	tween.tween_property(self, "volume_db", -80.0, duration)
	tween.tween_callback(Callable(self, "stop"))
