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


## Fixed direction, used by the debug capture so a recorded run is deterministic.
class Scripted extends MotionSource:
	var direction: Vector2 = Vector2.ZERO

	func _init(p_direction: Vector2 = Vector2.ZERO) -> void:
		direction = p_direction

	func get_direction() -> Vector2:
		return direction
