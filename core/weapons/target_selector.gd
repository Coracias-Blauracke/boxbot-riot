@abstract
class_name TargetSelector
extends Resource

## AT WHOM a weapon aims. Swappable per weapon, which opens a whole category of
## items on its own: a sniper that picks the healthiest enemy plays completely
## differently from a shotgun that picks the nearest, with no other change.
##
## Works on parallel arrays and returns an INDEX rather than a node, so the
## whole thing stays headless and allocation-free on the hot path.

## Returns the chosen index into `positions`/`models`, or -1 for no target.
@abstract func select(origin: Vector2, positions: PackedVector2Array, models: Array, max_range: float) -> int

func _in_range(origin: Vector2, position: Vector2, max_range: float) -> bool:
	return max_range <= 0.0 or origin.distance_squared_to(position) <= max_range * max_range
