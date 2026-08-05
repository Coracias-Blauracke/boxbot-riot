class_name SpawnNearPlayer
extends SpawnPattern

## Materialises a group beside a player rather than at the edge of the view.
## The ambush.
##
## `min_distance` is NOT optional and must stay well clear of the player's
## reach. A group that can appear on top of somebody is not difficulty, it is a
## coin flip - the player had no information and no move that would have helped.
## Landing just inside the view is the point; landing in their lap is not.

## Distance band from the chosen player. The floor is what keeps this fair.
@export var min_distance: float = 190.0
@export var max_distance: float = 310.0

## Radius the group is scattered over once its anchor is chosen.
@export var cluster_radius: float = 40.0

func positions(context: SpawnContext, count: int, rng: RunRandom) -> PackedVector2Array:
	# No living player to ambush - fall back to the middle of the view rather
	# than returning nothing, so a wave never silently stops spawning.
	if context.player_positions.is_empty():
		return _scatter(context.view_centre, count, cluster_radius, context, rng)

	# Which player is picked is deliberately a plain uniform roll for now. When
	# it needs to be "whoever is most isolated" or "whoever is healthiest", that
	# is TargetSelector again and belongs in its own resource rather than here.
	var index := rng.randi_in(RunRandom.Stream.SPAWNS, 0, context.player_positions.size() - 1)
	var target := context.player_positions[index]

	var angle := rng.randf_in(RunRandom.Stream.SPAWNS, 0.0, TAU)
	var distance := rng.randf_in(
		RunRandom.Stream.SPAWNS,
		minf(min_distance, max_distance),
		maxf(min_distance, max_distance)
	)
	var anchor := target + Vector2.RIGHT.rotated(angle) * distance

	# The floor is enforced against EVERY player, not just the one being
	# ambushed, and on every member rather than on the anchor. See
	# SpawnPattern._push_clear_of_players for why both of those are necessary.
	return _push_clear_of_players(
		_scatter(anchor, count, cluster_radius, context, rng),
		minf(min_distance, max_distance),
		context
	)
