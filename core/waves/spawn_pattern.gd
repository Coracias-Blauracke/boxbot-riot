@abstract
class_name SpawnPattern
extends Resource

## WHERE a group arrives. The fourth axis of the wave system, and the one that
## was missing.
##
## The other three already existed: WaveTable decides WHAT may appear, the
## budget decides HOW MUCH, and WaveDirector decides WHEN. Placement was a
## single hardcoded policy in the scene layer - always a random angle just off
## screen - so an ambush or an arrival from the arena rim was not expressible.
##
## Deliberately the same shape as SpreadPattern in core/weapons/: takes plain
## data, returns plain data, knows nothing about nodes. A pistol differs from a
## shotgun by one swapped resource, and a lurker should differ from a chaser the
## same way.

## One position per enemy in the group. Never fewer than one, even for count 0.
@abstract func positions(context: SpawnContext, count: int, rng: RunRandom) -> PackedVector2Array

## Shared helper: places `count` points around ONE anchor.
##
## The single anchor is the point. The old pipeline rolled a fresh position per
## enemy, so a group of three was three separate arrivals that happened to share
## a frame. Everything here scatters around one place instead.
func _scatter(
	centre: Vector2, count: int, radius: float, context: SpawnContext, rng: RunRandom
) -> PackedVector2Array:
	var result := PackedVector2Array()

	for index in maxi(1, count):
		var point := centre

		# The first member sits on the anchor; the rest ring it. A group of one
		# then lands exactly where the pattern intended, with no jitter to blur
		# a deliberately placed single enemy.
		if index > 0 and radius > 0.0:
			var angle := rng.randf_in(RunRandom.Stream.SPAWNS, 0.0, TAU)
			# sqrt, or the points bunch towards the centre of the disc - a
			# cluster of eight would look like a cluster of three with a halo.
			var distance := radius * sqrt(rng.randf_in(RunRandom.Stream.SPAWNS, 0.0, 1.0))
			point = centre + Vector2.RIGHT.rotated(angle) * distance

		if context != null and context.world != null:
			point = context.world.clamp_to_bounds(point)
		result.append(point)

	return result

## Pushes every point clear of EVERY player.
##
## Two mistakes this exists to prevent, both of which were made here first.
## Enforcing a distance on the group's ANCHOR says nothing about where its
## members land: a cluster of radius 40 around an anchor 190 away leaves its
## nearest member at 150. And a floor measured against only the TARGETED player
## still lets a group materialise in a second player's lap, which in co-op is
## the same unfairness with an extra step.
##
## A single pass. Pushing clear of one player can move a point towards another,
## and where players stand closer together than twice the radius no point
## satisfies everyone anyway - iterating would only oscillate.
##
## One case is unsatisfiable: a player against a wall, where pushing clear and
## staying in bounds contradict each other. Bounds win, because a group outside
## the arena would be unreachable.
func _push_clear_of_players(
	points: PackedVector2Array, radius: float, context: SpawnContext
) -> PackedVector2Array:
	if radius <= 0.0 or context == null or context.player_positions.is_empty():
		return points

	for i in points.size():
		for player in context.player_positions:
			var offset := points[i] - player
			var length := offset.length()
			if length >= radius:
				continue

			var direction := offset.normalized() if length > 0.001 else Vector2.RIGHT
			var pushed := player + direction * radius
			points[i] = (
				context.world.clamp_to_bounds(pushed) if context.world != null else pushed
			)

	return points
