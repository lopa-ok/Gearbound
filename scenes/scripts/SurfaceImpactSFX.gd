# filepath: /Users/lopa/test/scenes/scripts/SurfaceImpactSFX.gd
extends RigidBody3D
"""
Attach this script to your car root (RigidBody3D/VehicleBody3D).
Plays impact sounds when the car hits different surfaces. Surfaces are
selected by groups on the collided bodies (e.g., "surface_metal", "surface_wood",
"surface_gravel", "surface_grass"). If no group matches, uses the "default" stream.

Setup:
- Add this script to the car node.
- In the Inspector, assign AudioStreams in `surface_streams` for groups you use
  (add keys like surface_metal, surface_wood, surface_gravel, surface_asphalt, default).
- Optionally tweak `min_hit_speed` and `cooldown_sec`.
- Ensure the car node has collisions enabled and `contact_monitor` can be set.
"""

@export var min_hit_speed: float = 3.5 # m/s relative speed threshold to count as a hit
@export var cooldown_sec: float = 0.18  # minimum time between hit sounds
@export var volume_db: float = -2.0     # base volume; impact intensity is added
@export var pitch_base: float = 1.0
@export var pitch_intensity_scale: float = 0.035 # how much pitch scales with impact speed
@export var max_contacts_to_scan: int = 8
@export var surface_streams: Dictionary = {
	"surface_metal": null,
	"surface_wood": null,
	"surface_gravel": null,
	"surface_grass": null,
	"surface_concrete": null,
	"default": null,
}

var _cooldown_until_ms: int = 0
@onready var _impact_player: AudioStreamPlayer3D = _ensure_player()

func _ready():
	# Ensure we can read contact info from the physics state
	contact_monitor = true
	max_contacts_reported = max(max_contacts_to_scan, 4)

func _ensure_player() -> AudioStreamPlayer3D:
	var p := get_node_or_null("ImpactSFX") as AudioStreamPlayer3D
	if p:
		return p
	p = AudioStreamPlayer3D.new()
	p.name = "ImpactSFX"
	p.attenuation_filter_cutoff_hz = 18000.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = 6.0
	add_child(p)
	return p

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Cooldown gate
	if Time.get_ticks_msec() < _cooldown_until_ms:
		return
	var contact_count := state.get_contact_count()
	if contact_count <= 0:
		return
	# Limit how many contacts we scan and keep type explicit for Godot 4
	var scanned: int = min(contact_count, max_contacts_reported)
	for i in range(scanned):
		var other := state.get_contact_collider_object(i)
		if other == null:
			continue
		# Estimate relative impact speed at the contact point
		var lp: Vector3 = state.get_contact_local_position(i)
		var v_self: Vector3 = state.get_velocity_at_local_position(lp)
		var v_other: Vector3 = state.get_contact_collider_velocity_at_position(i)
		var rel_speed := (v_other - v_self).length()
		if rel_speed < min_hit_speed:
			continue
		var stream: AudioStream = _pick_stream_for(other)
		if stream == null:
			continue
		_impact_player.stream = stream
		# Scale pitch and volume by impact intensity
		_impact_player.pitch_scale = clamp(pitch_base + rel_speed * pitch_intensity_scale, 0.6, 1.5)
		_impact_player.volume_db = volume_db + clamp(rel_speed * 0.6, -6.0, 10.0)
		_impact_player.play()
		_cooldown_until_ms = Time.get_ticks_msec() + int(cooldown_sec * 1000.0)
		break

func _pick_stream_for(other: Object) -> AudioStream:
	if other is Node:
		var node := other as Node
		# First check explicit surface_ groups
		for key in surface_streams.keys():
			if key == "default":
				continue
			if node.is_in_group(str(key)) and surface_streams[key] is AudioStream:
				return surface_streams[key]
	# Fallback
	return surface_streams.get("default", null)
