# Multi-Lock Door System – Setup Guide

This project includes a multi-lock door, simple per-lock key checks, bone-based item carrying, light flicker, and pause-aware crosshair behavior.

Contents
- MultiLockDoor setup
- SimpleLock setup
- Key items
- HumanPlayer carrying and crouch
- Light flicker
- Pause crosshair
- Debugging tips

## MultiLockDoor
1. Add a Node3D and attach `scenes/scripts/interactables/MultiLockDoor.gd`.
2. Animation (optional):
   - Add an `AnimationPlayer` on the door node with an `open` animation (default name).
   - Set `use_animation = true` and tweak `animation_speed`.
   - If no animation, set `use_animation = false` and the door will rotate by `open_rotation_degrees`.
3. Interaction:
   - Enable `use_proximity_area` to auto-create a `UseArea` for interact.
   - If you want aim-gating like KeyDoor, keep `require_human_crosshair = true`.
   - To require holding Interact, set `require_interact_press = true`.
4. Locks:
   - Place your lock nodes anywhere in the scene.
   - On the door, set `lock_paths` to each lock node.
   - Set `locks_required` to how many locks must be unlocked.
   - Optional: `auto_open_on_final_unlock = true` to open immediately after the last required lock is unlocked (no extra interact).
5. Audio (optional): set `open_sfx_path` and `locked_sfx_path` to `AudioStreamPlayer3D` nodes.

## SimpleLock
1. Add a Node3D and attach `scenes/scripts/interactables/SimpleLock.gd`.
2. Configure:
   - `required_key_id` to the expected item id (e.g., `red_key`, `blue_key`).
   - `use_proximity_area` to enable proximity interact, or drive via door’s interact.
   - `require_human_crosshair` to force aim on the lock when interacting directly.
   - `consume_key` to remove the key when unlocked.
3. Animation (optional):
   - Add an `AnimationPlayer` with an `unlock` animation (default name).
   - Set `animation_player_path` if not a sibling.
   - Set `play_animation_on_unlock = true` and optionally `hide_after_animation = true`.
4. Wiring to door:
   - In the door, add this lock’s NodePath to `lock_paths`. The door listens to the lock’s `unlocked` signal automatically.

## Key Items
1. Use `scenes/scripts/PickupItem.gd` (already used by items like `KeyItem.tscn`).
2. Set per item:
   - `item_type = "key"`
   - `item_id` to match each lock’s `required_key_id`.
3. Optional, better in-hand visuals:
   - Set `held_model_scene` to a hand-optimized model. While carried, the world meshes are hidden and this model is shown.
   - Per-item hand alignment: `carry_item_offset` and `carry_item_rotation_deg` (overrides used by HumanPlayer when carried).

## HumanPlayer – Carrying and Crouch
- The player auto-attaches carried items to a hand via `BoneAttachment3D` when possible.
- Tuning exports in `scenes/scripts/HumanPlayer.gd`:
  - Hand: `carry_use_bone`, `carry_bone_name`, `carry_bone_offset`, `carry_bone_rotation_deg`.
  - Per-item overrides are read from the item (`carry_item_offset`, `carry_item_rotation_deg`).
  - Crouch: `crouch_speed_multiplier`, `crouch_height_scale`, `crouch_camera_drop`.
  - Clearance check avoids false obstructions using a headroom shape check; toggle logs with `crouch_debug`.
- Groups: Human player is in groups `human_player`, `player`.

## Light Flicker
- Attach `scripts/FlickerLight.gd` to any OmniLight3D or SpotLight3D (now extends Light3D).
- Key exports: `base_energy`, `min_factor`, `max_factor`, `use_noise`, `noise_frequency`.
- Random blinks: enable `random_blinks` and adjust intervals; deterministic with `rng_seed`.
- Pause-aware by default (`pause_when_paused = true`).

## Pause Crosshair
- `scenes/scripts/ui/PauseManager.gd` hides the HumanPlayer crosshair while paused and restores it on resume.
- Ensure your pause menu toggles `get_tree().paused`. The included `PauseMenu.tscn` + `PauseManager.gd` handle this.

## Debugging Tips
- Door: call `debug_dump()` on `MultiLockDoor.gd` to print lock status and requirements.
- Lock: call `debug_dump(player)` on `SimpleLock.gd` to print whether the player’s carried key matches.
- Player: use `debug_dump_carry_info()` and `debug_list_bones()`.

## Test Flow
1. Give the player `KeyItem.tscn` with `item_id = red_key` and try unlocking a lock with `required_key_id = red_key`.
2. Confirm lock plays unlock animation and emits `unlocked`.
3. After all required locks are open, the door should auto-open (if `auto_open_on_final_unlock = true`).
4. Open the pause menu; crosshair should hide. Resume; crosshair should reappear.
5. Attach `FlickerLight.gd` to a light to see flicker and random blinks.
