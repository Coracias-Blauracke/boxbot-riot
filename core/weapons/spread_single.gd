class_name SpreadSingle
extends SpreadPattern

## One projectile, deflected somewhere inside the inaccuracy cone.
## With SPREAD_ANGLE at 0 it fires perfectly straight.

func directions(aim: Vector2, spread_degrees: float, rng: RunRandom) -> PackedVector2Array:
	return PackedVector2Array([aim.rotated(_jitter(spread_degrees, rng))])
