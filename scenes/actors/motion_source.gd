class_name MotionSource
extends RefCounted

## "Who decides where this actor walks." One player, one source.
##
## Split out from the start because local co-op needs device_id -> player index
## from day one. Retrofitting four players later would mean reworking the
## character scene, which is the most expensive moment to change it.

func get_direction() -> Vector2:
	return Vector2.ZERO


## device_id -1 is the keyboard; 0..3 are gamepads.
class Device extends MotionSource:
	var device_id: int = -1

	func _init(p_device_id: int = -1) -> void:
		device_id = p_device_id

	func get_direction() -> Vector2:
		if device_id < 0:
			return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")

		# Read the pad directly rather than through the InputMap: actions are
		# global in Godot, so four pads sharing one action set would move every
		# player at once.
		var raw := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		)
		return raw if raw.length() > 0.2 else Vector2.ZERO


## First source that reports movement wins. Lets player 1 use the keyboard and
## a gamepad interchangeably without picking one at startup.
class Combined extends MotionSource:
	var sources: Array[MotionSource] = []

	func _init(p_sources: Array[MotionSource] = []) -> void:
		sources = p_sources

	func get_direction() -> Vector2:
		for source in sources:
			var direction := source.get_direction()
			if direction != Vector2.ZERO:
				return direction
		return Vector2.ZERO


## Movement driven by a player's device binding.
##
## Wraps PlayerInput rather than replacing it, so a capture run can swap in
## Scripted below without the player losing the device that also drives their
## shop panel. Walking and buying must not be able to disagree about who owns
## which pad.
class FromInput extends MotionSource:
	var input: PlayerInput

	func _init(p_input: PlayerInput = null) -> void:
		input = p_input

	func get_direction() -> Vector2:
		return input.movement() if input != null else Vector2.ZERO


## Fixed direction, used by the debug capture so a recorded run is deterministic.
class Scripted extends MotionSource:
	var direction: Vector2 = Vector2.ZERO

	func _init(p_direction: Vector2 = Vector2.ZERO) -> void:
		direction = p_direction

	func get_direction() -> Vector2:
		return direction
