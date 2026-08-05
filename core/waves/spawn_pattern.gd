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
