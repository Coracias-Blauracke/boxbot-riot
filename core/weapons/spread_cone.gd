class_name SpreadCone
extends SpreadPattern

## Several projectiles scattered randomly through the cone. The shotgun.
## Random rather than evenly spaced, so two shots never pattern identically.

@export var count: int = 8

func projectile_count() -> int:
	return count

func directions(aim: Vector2, spread_degrees: float, rng: RunRandom) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in maxi(1, count):
		result.append(aim.rotated(_jitter(spread_degrees, rng)))
	return result
