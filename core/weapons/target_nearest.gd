class_name TargetNearest
extends TargetSelector

## The default. What most weapons should do.

func select(origin: Vector2, positions: PackedVector2Array, _models: Array, max_range: float) -> int:
	var best := -1
	var best_distance := INF
	for i in positions.size():
		if not _in_range(origin, positions[i], max_range):
			continue
		var distance := origin.distance_squared_to(positions[i])
		if distance < best_distance:
			best_distance = distance
			best = i
	return best
