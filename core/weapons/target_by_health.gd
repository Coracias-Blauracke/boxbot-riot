class_name TargetByHealth
extends TargetSelector

## Picks the weakest or the toughest enemy in range.
##
## LOWEST finishes off wounded enemies, which suits fast weapons; HIGHEST goes
## for elites and bosses, which suits slow heavy hitters. One class, two very
## different weapon identities.

enum Mode { LOWEST, HIGHEST }

@export var mode: Mode = Mode.LOWEST

## Ties are broken by proximity so the choice never flickers between two
## equally wounded enemies.
func select(origin: Vector2, positions: PackedVector2Array, models: Array, max_range: float) -> int:
	var best := -1
	var best_hp := INF if mode == Mode.LOWEST else -INF
	var best_distance := INF

	for i in positions.size():
		if not _in_range(origin, positions[i], max_range):
			continue

		var model := models[i] as EntityModel
		if model == null or not model.is_alive:
			continue

		var hp := model.current_hp
		var distance := origin.distance_squared_to(positions[i])
		var better := hp < best_hp if mode == Mode.LOWEST else hp > best_hp

		if better or (is_equal_approx(hp, best_hp) and distance < best_distance):
			best_hp = hp
			best_distance = distance
			best = i

	return best
