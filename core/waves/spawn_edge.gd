class_name SpawnEdge
extends SpawnPattern

## From the arena wall, however far away that is.
##
## Used to be the unreachable fallback inside the old spawner. As a pattern in
## its own right it is what a slow siege enemy wants: it walks in from the rim
## and the players watch it coming for a long time, which is a different kind of
## pressure from something appearing at the edge of the frame.

@export var cluster_radius: float = 60.0

func positions(context: SpawnContext, count: int, rng: RunRandom) -> PackedVector2Array:
	var anchor := (
		context.world.random_point_on_edge(rng)
		if context.world != null
		else context.view_centre
	)
	return _scatter(anchor, count, cluster_radius, context, rng)
