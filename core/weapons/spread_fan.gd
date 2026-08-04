class_name SpreadFan
extends SpreadPattern

## Several projectiles spaced evenly across the cone, with optional jitter on
## top. Reads as a deliberate volley rather than a scatter - good for magic
## weapons and triple-shots where the shape should be recognisable.

@export var count: int = 3
## 0 keeps the fan perfectly regular; higher values loosen it.
@export var jitter_ratio: float = 0.0

func projectile_count() -> int:
	return count

func directions(aim: Vector2, spread_degrees: float, rng: RunRandom) -> PackedVector2Array:
	var total := maxi(1, count)
	var result := PackedVector2Array()

	if total == 1:
		result.append(aim.rotated(_jitter(spread_degrees * jitter_ratio, rng)))
		return result

	var half := deg_to_rad(spread_degrees)
	for i in total:
		# Spread evenly from -half to +half across the whole fan.
		var t := float(i) / float(total - 1)
		var angle := lerpf(-half, half, t) + _jitter(spread_degrees * jitter_ratio, rng)
		result.append(aim.rotated(angle))
	return result
