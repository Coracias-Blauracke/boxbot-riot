class_name SpawnRing
extends SpawnPattern

## Just beyond the edge of what is on screen, not at the arena wall.
##
## The arena is much larger than the view, so spawning at the wall would have
## enemies walking in from off-map for ten seconds before they threatened
## anybody. They arrive from just out of sight instead.
##
## This is the default and the old behaviour - with one difference that matters:
## the whole group now shares one angle.

## How far past the corner of the view the ring sits. Measured on the view's
## DIAGONAL, so it must stay above 1.0 or enemies pop into existence on screen.
@export var view_margin: float = 1.12

## Radius the group is scattered over once its angle is chosen.
@export var cluster_radius: float = 46.0

func positions(context: SpawnContext, count: int, rng: RunRandom) -> PackedVector2Array:
	return _scatter(_anchor(context, rng), count, cluster_radius, context, rng)

func _anchor(context: SpawnContext, rng: RunRandom) -> Vector2:
	var centre := context.view_centre
	var ring := context.view_size.length() * 0.5 * view_margin

	for attempt in 8:
		var angle := rng.randf_in(RunRandom.Stream.SPAWNS, 0.0, TAU)
		var candidate := centre + Vector2.RIGHT.rotated(angle) * ring

		if context.world == null or context.world.is_inside(candidate):
			return candidate

		# Outside the arena: pull it back to the wall and take it only if that
		# still leaves it off screen. Near a corner most angles fail this.
		var clamped := context.world.clamp_to_bounds(candidate)
		var offset := clamped - centre
		if absf(offset.x) > context.view_size.x * 0.5 or absf(offset.y) > context.view_size.y * 0.5:
			return clamped

	# Boxed in on every side - fall back to the arena rim.
	return context.world.random_point_on_edge(rng) if context.world != null else centre
