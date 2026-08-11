class_name SpawnScatter
extends SpawnPattern

## Around whoever asked. The placement a spawn REQUEST normally wants: a splitter
## bursts where it died, a hive drops its brood beside itself.
##
## The fifth pattern, and the first that reads SpawnContext.anchor rather than
## the camera or the players. That is the only thing separating it from the other
## four - which is the point of placement being an axis: a request can be given
## SpawnRing instead and its children will walk in from off screen, with nothing
## here or in the view changing.

## How far the members may land from the anchor. 0 stacks them all on it.
##
## The first member always sits exactly on the anchor - see SpawnPattern._scatter
## - so a request for one lands precisely where it was asked for.
@export var radius: float = 34.0

## DELIBERATELY NOT pushed clear of players, unlike the patterns that arrive from
## off screen.
##
## That rule exists because a group materialising in your lap is unfair: you had
## no information and no move that would have helped. Neither is true here. The
## thing that split was already standing there, in view, being shot at - moving
## its children away from the player would be hiding a consequence the player
## earned rather than preventing an ambush.
func positions(context: SpawnContext, count: int, rng: RunRandom) -> PackedVector2Array:
	var centre := context.anchor if context != null else Vector2.ZERO
	return _scatter(centre, count, radius, context, rng)
