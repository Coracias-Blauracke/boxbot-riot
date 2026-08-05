@abstract
class_name SpreadPattern
extends Resource

## HOW MANY outputs a shot produces and how they are arranged around the aim.
##
## The cone half-angle comes from the SPREAD_ANGLE stat rather than from here,
## so "-20% inaccuracy" items work on every weapon without any of them knowing
## about the item.

## Returns one normalised direction per projectile.
@abstract func directions(aim: Vector2, spread_degrees: float, rng: RunRandom) -> PackedVector2Array

func projectile_count() -> int:
	return 1

## Shared helper: a random offset inside the cone, in radians.
func _jitter(spread_degrees: float, rng: RunRandom) -> float:
	if spread_degrees <= 0.0:
		return 0.0
	var half := deg_to_rad(spread_degrees)
	return rng.randf_in(RunRandom.Stream.COMBAT, -half, half)
