class_name ChaseBehavior
extends MovementBehavior

## Walks straight at the target. The baseline enemy.

## Stops closing in once this near, so a swarm does not pile into one point.
@export var stop_distance: float = 0.0

func get_direction(_host: Variant, self_position: Vector2, target_position: Vector2, _delta: float) -> Vector2:
	var offset := target_position - self_position
	if offset.length() <= stop_distance:
		return Vector2.ZERO
	return offset.normalized()
