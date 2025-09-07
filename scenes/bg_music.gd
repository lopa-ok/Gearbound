extends AudioStreamPlayer

func fade_out_music(duration: float = 2.0):
	var tween = create_tween()
	tween.tween_property(self, "volume_db", -80.0, duration)
	tween.tween_callback(Callable(self, "stop"))
