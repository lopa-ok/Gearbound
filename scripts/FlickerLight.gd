# Attach to a Light3D (OmniLight3D or SpotLight3D) to make it flicker.
extends Light3D

@export var base_energy: float = 1.0
@export var min_factor: float = 0.7       # minimum brightness factor
@export var max_factor: float = 1.1       # maximum brightness factor
@export var use_noise: bool = true        # smooth noise flicker; false = sine fallback
@export var noise_frequency: float = 6.0  # Hz-like rate for noise/sine
@export var pause_when_paused: bool = true

# Occasional blinks (brief outages)
@export var random_blinks: bool = true
@export var blink_interval_min: float = 2.0
@export var blink_interval_max: float = 6.0
@export var blink_min_time: float = 0.03
@export var blink_max_time: float = 0.12
@export var rng_seed: int = 0

var _time: float = 0.0
var _next_blink_in: float = 0.0
var _blink_remaining: float = 0.0
var _rng := RandomNumberGenerator.new()
var _noise: FastNoiseLite

func _ready():
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	if base_energy <= 0.0:
		base_energy = light_energy
	_schedule_next_blink()
	if use_noise:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_noise.frequency = 1.0  # we scale with time ourselves

func _process(delta: float) -> void:
	if pause_when_paused and get_tree().paused:
		return
	_time += delta
	if random_blinks:
		if _blink_remaining > 0.0:
			_blink_remaining -= delta
			_set_energy(0.0)
			if _blink_remaining <= 0.0:
				_schedule_next_blink()
			return
		else:
			_next_blink_in -= delta
			if _next_blink_in <= 0.0:
				_blink_remaining = _rng.randf_range(blink_min_time, blink_max_time)
				# keep energy update in next frame after blinking starts
				_set_energy(0.0)
				return
	# Continuous flicker
	var f := _compute_factor()
	_set_energy(base_energy * f)

func _compute_factor() -> float:
	var t := _time * noise_frequency
	var v: float
	if use_noise and _noise:
		# FastNoiseLite returns ~[-1,1], remap to [0,1]
		v = (_noise.get_noise_1d(t) + 1.0) * 0.5
	else:
		v = (sin(t * TAU) + 1.0) * 0.5
	return lerp(min_factor, max_factor, clamp(v, 0.0, 1.0))

func _set_energy(v: float) -> void:
	light_energy = max(0.0, v)

func _schedule_next_blink():
	_next_blink_in = _rng.randf_range(blink_interval_min, blink_interval_max)
