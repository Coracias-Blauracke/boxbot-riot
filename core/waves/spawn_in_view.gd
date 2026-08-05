class_name SpawnInView
extends SpawnPattern

## Anywhere on screen, as long as it is not in somebody's lap.
##
## SpawnRing answers "they walked in from off screen". This answers "they were
## already here" - and it is the more aggressive of the two, because there is no
## approach to read and react to. The group is simply there.
##
## That is exactly why `clear_radius` is not optional and is enforced against
## every player rather than the nearest one.

## Nothing lands within this of ANY living player.
@export var clear_radius: float = 230.0

## Keeps the anchor off the very edge of the frame, where a group would be half
## cut off at the instant it appears.
@export var view_inset: float = 40.0

@export var cluster_radius: float = 40.0

func positions(context: SpawnContext, count: int, rng: RunRandom) -> PackedVector2Array:
	return _push_clear_of_players(
		_scatter(_anchor(context, rng), count, cluster_radius, context, rng),
		clear_radius,
		context
	)

func _anchor(context: SpawnContext, rng: RunRandom) -> Vector2:
	var half := context.view_size * 0.5 - Vector2.ONE * view_inset
	half = Vector2(maxf(half.x, 0.0), maxf(half.y, 0.0))

	var best := context.view_centre
	var best_clearance := -1.0

	# Rejection sampling with a fallback rather than a loop that might not end.
	# Four players spread across a small view can leave NO clear point at all,
	# and returning nothing would stall the wave silently - so the roomiest
	# candidate wins instead, and _push_clear_of_players tidies up after it.
	for attempt in 12:
		var candidate := context.view_centre + Vector2(
			rng.randf_in(RunRandom.Stream.SPAWNS, -half.x, half.x),
			rng.randf_in(RunRandom.Stream.SPAWNS, -half.y, half.y)
		)
		if context.world != null:
			candidate = context.world.clamp_to_bounds(candidate)

		var clearance := _clearance(candidate, context)
		if clearance >= clear_radius:
			return candidate
		if clearance > best_clearance:
			best_clearance = clearance
			best = candidate

	return best

## Distance to the NEAREST player, or INF when there are none left standing.
func _clearance(point: Vector2, context: SpawnContext) -> float:
	var nearest := INF
	for player in context.player_positions:
		nearest = minf(nearest, point.distance_to(player))
	return nearest
